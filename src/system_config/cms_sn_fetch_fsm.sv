module cms_sn_fetch_fsm (
  input  logic  aclk,
  input  logic  aresetn,
  // From controller
  input  logic [17:0] s_axi_ctrl_ARADDR,
  input  logic [2:0]  s_axi_ctrl_ARPROT,
  output logic [0:0]  s_axi_ctrl_ARREADY,
  input  logic [0:0]  s_axi_ctrl_ARVALID,
  input  logic [17:0] s_axi_ctrl_AWADDR,
  input  logic [2:0]  s_axi_ctrl_AWPROT,
  output logic [0:0]  s_axi_ctrl_AWREADY,
  input  logic [0:0]  s_axi_ctrl_AWVALID,
  input  logic [0:0]  s_axi_ctrl_BREADY,
  output logic [1:0]  s_axi_ctrl_BRESP,
  output logic [0:0]  s_axi_ctrl_BVALID,
  output logic [31:0] s_axi_ctrl_RDATA,
  input  logic [0:0]  s_axi_ctrl_RREADY,
  output logic [1:0]  s_axi_ctrl_RRESP,
  output logic [0:0]  s_axi_ctrl_RVALID,
  input  logic [31:0] s_axi_ctrl_WDATA,
  output logic [0:0]  s_axi_ctrl_WREADY,
  input  logic [3:0]  s_axi_ctrl_WSTRB,
  input  logic [0:0]  s_axi_ctrl_WVALID,
  // To CMS
  output logic [17:0] m_axi_ctrl_ARADDR,
  output logic [2:0]  m_axi_ctrl_ARPROT,
  input  logic [0:0]  m_axi_ctrl_ARREADY,
  output logic [0:0]  m_axi_ctrl_ARVALID,
  output logic [17:0] m_axi_ctrl_AWADDR,
  output logic [2:0]  m_axi_ctrl_AWPROT,
  input  logic [0:0]  m_axi_ctrl_AWREADY,
  output logic [0:0]  m_axi_ctrl_AWVALID,
  output logic [0:0]  m_axi_ctrl_BREADY,
  input  logic [1:0]  m_axi_ctrl_BRESP,
  input  logic [0:0]  m_axi_ctrl_BVALID,
  input  logic [31:0] m_axi_ctrl_RDATA,
  output logic [0:0]  m_axi_ctrl_RREADY,
  input  logic [1:0]  m_axi_ctrl_RRESP,
  input  logic [0:0]  m_axi_ctrl_RVALID,
  output logic [31:0] m_axi_ctrl_WDATA,
  input  logic [0:0]  m_axi_ctrl_WREADY,
  output logic [3:0]  m_axi_ctrl_WSTRB,
  output logic [0:0]  m_axi_ctrl_WVALID,
  // Serial Number
  output logic             card_sn_vld,
  output logic [7:0]       card_sn_len,
  output logic [0:15][7:0] card_sn,
  // Status
  output logic             error_boot_timeout,
  output logic             error_bad_axil_transaction,
  output logic             error_card_info_length,
  output logic             error_bad_info_parse
);

`ifdef SYNTHESIS
  localparam int DEBOUNCE_CNT = 50*1000*1000;  // 50M 50MHz clock cycles = 1s
  localparam int BOOT_WAIT = 50*1000*1000;     // 50M 50MHz clock cycles = 1s
  localparam int BOOT_TIMEOUT = 250*1000*1000; // 250M 50MHz clock cycles = 5s
`else
  localparam int DEBOUNCE_CNT = 100;
  localparam int BOOT_WAIT = 50;
  localparam int BOOT_TIMEOUT = 250;
`endif
  localparam int TIMER_WID = $clog2(BOOT_TIMEOUT+1);

  localparam logic [17:0] ADDR__MB_RESETN_REG       = 18'h20000;
  localparam logic [17:0] ADDR__REG_MAP_ID_REG      = 18'h28000;
  localparam logic [17:0] ADDR__CONTROL_REG         = 18'h28018;
  localparam logic [17:0] ADDR__HOST_MSG_OFFSET_REG = 18'h28300;
  localparam logic [17:0] ADDR__HOST_STATUS2_REG    = 18'h2830C;
  localparam logic [17:0] ADDR__MAILBOX_BASE        = 18'h28000;

  localparam logic [31:0] VALUE__REG_MAP_ID = 32'h74736574;

  localparam logic [7:0]  KEY__CARD_SN = 8'h21;

  localparam logic [1:0]  AXIL__RESP_OKAY = 2'b00;

  typedef enum logic [4:0] {
    RESET                      = 0,
    RESET_DEBOUNCE             = 1,
    DEASSERT_MB_RESET          = 2,
    INITIAL_BOOT_WAIT          = 3,
    CHECK_REG_MAP_ID           = 4,
    CHECK_REG_MAP_READY        = 5,
    GET_HOST_MSG_OFFSET        = 6,
    LATCH_HOST_MSG_OFFSET      = 7,
    CARD_INFO_QUERY_REQ        = 8,
    MAILBOX_REQ                = 9,
    MAILBOX_PENDING            = 10,
    READ_CARD_INFO_LENGTH      = 11,
    LATCH_CARD_INFO_LENGTH     = 12,
    READ_MAILBOX_REG           = 13,
    LATCH_MAILBOX_REG          = 14,
    READ_NXT_MAILBOX_REG       = 15,
    CARDINFO_READY             = 16,
    SN_PARSE_DONE              = 17,
    ERROR_BAD_AXIL_TRANSACTION = 18,
    ERROR_BOOT_TIMEOUT         = 19,
    ERROR_CARD_INFO_LENGTH     = 20,
    ERROR_BAD_INFO_PARSE       = 21,
    ASSERT_MB_RESET            = 22,
    DONE                       = 23
  } state_t;

  typedef enum logic [3:0] {
    AXIL_RESET = 0,
    AXIL_IDLE  = 1,
    AXIL_AW_W  = 2,
    AXIL_AW    = 3,
    AXIL_W     = 4,
    AXIL_B     = 5,
    AXIL_AR    = 6,
    AXIL_R     = 7,
    AXIL_DONE  = 8,
    AXIL_ERROR = 9
  } axil_state_t;

  typedef enum logic [3:0] {
    PARSE_RESET       = 0,
    PARSE_IDLE        = 1,
    PARSE_GET_KEY     = 2,
    PARSE_CHECK_KEY   = 3,
    PARSE_GET_LEN     = 4,
    PARSE_SKIP_FIELD  = 5,
    PARSE_FIELD       = 6,
    PARSE_FIELD_BYTES = 7,
    PARSE_DONE        = 8,
    PARSE_ERROR       = 9
  } parse_state_t;

  // Signals
  state_t state;
  state_t nxt_state;

  logic   done;

  logic                 reset_timer;
  logic                 inc_timer;
  logic [TIMER_WID-1:0] timer;

  logic        wr_req;
  logic        rd_req;

  logic        awvalid;
  logic [17:0] awaddr;
  logic        wvalid;
  logic [31:0] wdata;
  logic        bready;
  logic        arvalid;
  logic [17:0] araddr;
  logic        rready;
  logic [31:0] rdata;

  logic        latch_host_msg_offset;
  logic [17:0] addr_mailbox;

  logic        latch_info_data;
  logic        latch_info_len;
  logic [11:0] info_len;

  logic        reset_idx;
  logic        inc_idx;
  logic [11:0] idx;

  logic        reset_byte_idx;
  logic        inc_byte_idx;
  logic [1:0]  byte_idx;

  logic [7:0] cardinfo [128];

  axil_state_t axil_state;
  axil_state_t nxt_axil_state;

  parse_state_t parse_state;
  parse_state_t nxt_parse_state;

  logic       reset_parse_idx;
  logic       inc_parse_idx;
  logic [6:0] parse_idx_incr;
  logic [6:0] parse_idx;
  logic [6:0] parse_idx_r;
  logic       parse_idx_oflow;
  logic       latch_key;
  logic       latch_len;
  logic       latch_value;

  logic [7:0] current_byte;
  logic [7:0] key;
  logic [7:0] field_len;
  logic [7:0] value_bytes;

  logic             sn_valid;
  logic [0:15][7:0] sn;

  logic       __error_boot_timeout;
  logic       __error_bad_axil_transaction;
  logic       __error_card_info_length;
  logic       __error_bad_info_parse;

  // Main FSM
  initial state = RESET;
  always @(posedge aclk) begin
    if (!aresetn) state <= RESET;
    else          state <= nxt_state;
  end

  always_comb begin
    nxt_state = state;
    reset_timer = 1'b0;
    inc_timer = 1'b0;
    sn_valid = 1'b0;
    wr_req = 1'b0;
    awaddr = '0;
    wdata = '0;
    rd_req = 1'b0;
    araddr = '0;
    latch_host_msg_offset = 1'b0;
    latch_info_len = 1'b0;
    reset_idx = 1'b0;
    inc_idx = 1'b0;
    reset_byte_idx = 1'b0;
    inc_byte_idx = 1'b0;
    __error_boot_timeout = 1'b0;
    __error_bad_axil_transaction = 1'b0;
    __error_card_info_length = 1'b0;
    __error_bad_info_parse = 1'b0;
    case (state)
      RESET : begin
        reset_timer = 1'b1;
        nxt_state = RESET_DEBOUNCE;
      end
      RESET_DEBOUNCE : begin
        inc_timer = 1'b1;
        if (timer == DEBOUNCE_CNT) nxt_state = DEASSERT_MB_RESET;
      end
      DEASSERT_MB_RESET : begin
        reset_timer = 1'b1;
        wr_req = 1'b1;
        awaddr = ADDR__MB_RESETN_REG;
        wdata = 32'h1;
        if (axil_state == AXIL_DONE)       nxt_state = INITIAL_BOOT_WAIT;
        else if (axil_state == AXIL_ERROR) nxt_state = ERROR_BAD_AXIL_TRANSACTION;
      end
      INITIAL_BOOT_WAIT : begin
        inc_timer = 1'b1;
        if (timer == BOOT_WAIT) nxt_state = CHECK_REG_MAP_ID;
      end
      CHECK_REG_MAP_ID : begin
        inc_timer = 1'b1;
        rd_req = 1'b1;
        araddr = ADDR__REG_MAP_ID_REG;
        if (axil_state == AXIL_DONE && rdata == VALUE__REG_MAP_ID) nxt_state = CHECK_REG_MAP_READY;
        else if (axil_state == AXIL_ERROR) nxt_state = ERROR_BAD_AXIL_TRANSACTION;
        else if (timer == BOOT_TIMEOUT) nxt_state = ERROR_BOOT_TIMEOUT;
      end
      CHECK_REG_MAP_READY: begin
        rd_req = 1'b1;
        araddr = ADDR__HOST_STATUS2_REG;
        if (axil_state == AXIL_DONE) begin
          if (rdata[0] == 1'b1) nxt_state = GET_HOST_MSG_OFFSET;
        end else if (axil_state == AXIL_ERROR) nxt_state = ERROR_BAD_AXIL_TRANSACTION;
      end
      GET_HOST_MSG_OFFSET: begin
        rd_req = 1'b1;
        araddr = ADDR__HOST_MSG_OFFSET_REG;
        if (axil_state == AXIL_DONE) nxt_state = LATCH_HOST_MSG_OFFSET;
        else if (axil_state == AXIL_ERROR) nxt_state = ERROR_BAD_AXIL_TRANSACTION;
      end
      LATCH_HOST_MSG_OFFSET: begin
        latch_host_msg_offset = 1'b1;
        nxt_state = CARD_INFO_QUERY_REQ;
      end
      CARD_INFO_QUERY_REQ: begin
        wr_req = 1'b1;
        awaddr = addr_mailbox;
        wdata = 32'h04000000;
        if (axil_state == AXIL_DONE) nxt_state = MAILBOX_REQ;
        else if (axil_state == AXIL_ERROR) nxt_state = ERROR_BAD_AXIL_TRANSACTION;
      end
      MAILBOX_REQ: begin
        wr_req = 1'b1;
        awaddr = ADDR__CONTROL_REG;
        wdata = 32'h20;
        if (axil_state == AXIL_DONE) nxt_state = MAILBOX_PENDING;
        else if (axil_state == AXIL_ERROR) nxt_state = ERROR_BAD_AXIL_TRANSACTION;
      end
      MAILBOX_PENDING : begin
        rd_req = 1'b1;
        araddr = ADDR__CONTROL_REG;
        if (axil_state == AXIL_DONE) begin
          if (rdata[5] == 1'b0) nxt_state = READ_CARD_INFO_LENGTH;
          else if (axil_state == AXIL_ERROR) nxt_state = ERROR_BAD_AXIL_TRANSACTION;
        end
      end
      READ_CARD_INFO_LENGTH: begin
        rd_req = 1'b1;
        araddr = addr_mailbox;
        if (axil_state == AXIL_DONE) begin
          if (rdata[11:0] > 0 && rdata[11:0] <= 12'h128) nxt_state = LATCH_CARD_INFO_LENGTH;
          else nxt_state = ERROR_CARD_INFO_LENGTH;
        end else if (axil_state == AXIL_ERROR) nxt_state = ERROR_BAD_AXIL_TRANSACTION;
      end
      LATCH_CARD_INFO_LENGTH: begin
        latch_info_len = 1'b1;
        reset_idx = 1'b1;
        nxt_state = READ_MAILBOX_REG;
      end
      READ_MAILBOX_REG : begin
        rd_req = 1'b1;
        araddr = addr_mailbox + idx + 4;
        reset_byte_idx = 1'b1;
        if (axil_state == AXIL_DONE) nxt_state = LATCH_MAILBOX_REG;
        else if (axil_state == AXIL_ERROR) nxt_state = ERROR_BAD_AXIL_TRANSACTION;
      end
      LATCH_MAILBOX_REG : begin
        latch_info_data = 1'b1;
        inc_byte_idx = 1'b1;
        if (idx + byte_idx + 1 == info_len) nxt_state = CARDINFO_READY;
        else if (byte_idx == 3) nxt_state = READ_NXT_MAILBOX_REG;
      end
      READ_NXT_MAILBOX_REG : begin
        inc_idx = 1'b1;
        nxt_state = READ_MAILBOX_REG;
      end
      CARDINFO_READY : begin
        if (parse_state == PARSE_DONE) nxt_state = SN_PARSE_DONE;
        else if (parse_state == PARSE_ERROR) nxt_state = ERROR_BAD_INFO_PARSE;
      end
      SN_PARSE_DONE : begin
        sn_valid = 1'b1;
        nxt_state = ASSERT_MB_RESET;
      end
      ERROR_BOOT_TIMEOUT : begin
        __error_boot_timeout = 1'b1;
        nxt_state = ASSERT_MB_RESET;
      end
      ERROR_BAD_AXIL_TRANSACTION : begin
        __error_bad_axil_transaction = 1'b1;
        nxt_state = ASSERT_MB_RESET;
      end
      ERROR_CARD_INFO_LENGTH: begin
        __error_card_info_length = 1'b1;
        nxt_state = ASSERT_MB_RESET;
      end
      ERROR_BAD_INFO_PARSE : begin
        __error_bad_info_parse = 1'b1;
        nxt_state = ASSERT_MB_RESET;
      end
      ASSERT_MB_RESET : begin
        wr_req = 1'b1;
        awaddr = ADDR__MB_RESETN_REG;
        wdata = 32'h0;
        if (axil_state == AXIL_DONE || axil_state == AXIL_ERROR) nxt_state = DONE;
      end
      DONE : begin
      end
    endcase
  end

  initial timer = 0;
  always @(posedge aclk) begin
    if (reset_timer) timer <= '0;
    else if (inc_timer) timer <= timer + 1;
  end

  initial addr_mailbox = ADDR__MAILBOX_BASE;
  always @(posedge aclk) if (latch_host_msg_offset) addr_mailbox <= ADDR__MAILBOX_BASE + rdata[17:0];

  initial info_len = '0;
  always @(posedge aclk) if (latch_info_len) info_len <= rdata[11:0];

  initial idx = '0;
  always @(posedge aclk) begin
    if (reset_idx) idx <= 0;
    else if (inc_idx) idx <= idx + 4;
  end

  initial byte_idx = '0;
  always @(posedge aclk) begin
    if (reset_byte_idx) byte_idx <= 0;
    else if (inc_byte_idx) byte_idx <= byte_idx + 1;
  end

  initial cardinfo = '{default: 0};
  always @(posedge aclk) begin
    if (latch_info_data) begin
      cardinfo[idx+byte_idx] <= rdata[byte_idx*8 +: 8];
    end
  end

  // Parse state machine
  initial parse_state = PARSE_RESET;
  always @(posedge aclk) begin
    if (!aresetn) parse_state <= PARSE_RESET;
    else          parse_state <= nxt_parse_state;
  end

  always_comb begin
    nxt_parse_state = parse_state;
    reset_parse_idx = 1'b0;
    parse_idx_incr = '0;
    latch_key = 1'b0;
    latch_len = 1'b0;
    latch_value = 1'b0;
    case (parse_state)
      PARSE_RESET : begin
        nxt_parse_state = PARSE_IDLE;
      end
      PARSE_IDLE : begin
        reset_parse_idx = 1'b1;
        if (state == CARDINFO_READY) nxt_parse_state = PARSE_GET_KEY;
      end
      PARSE_GET_KEY : begin
        latch_key = 1'b1;
        parse_idx_incr = 1;
        if (parse_idx_oflow) nxt_parse_state = PARSE_ERROR;
        else nxt_parse_state = PARSE_GET_LEN;
      end
      PARSE_GET_LEN : begin
        latch_len = 1'b1;
        if (parse_idx_oflow) nxt_parse_state = PARSE_ERROR;
        else nxt_parse_state = PARSE_CHECK_KEY;
      end
      PARSE_CHECK_KEY : begin
        if (key == KEY__CARD_SN) nxt_parse_state = PARSE_FIELD;
        else nxt_parse_state = PARSE_SKIP_FIELD;
      end
      PARSE_SKIP_FIELD : begin
        parse_idx_incr = field_len+1;
        nxt_parse_state = PARSE_GET_KEY;
      end
      PARSE_FIELD : begin
        parse_idx_incr = 1;
        nxt_parse_state = PARSE_FIELD_BYTES;
      end
      PARSE_FIELD_BYTES : begin
        latch_value = 1'b1;
        parse_idx_incr = 1;
        if (parse_idx_oflow) nxt_parse_state = PARSE_ERROR;
        else if (value_bytes == field_len-1) begin
          if (current_byte == 8'h0) nxt_parse_state = PARSE_DONE;
          else nxt_parse_state = PARSE_ERROR;
        end
      end
      PARSE_DONE : begin
        nxt_parse_state = PARSE_IDLE;
      end
      PARSE_ERROR : begin
        nxt_parse_state = PARSE_IDLE;
      end
    endcase
  end

  initial parse_idx_r = 0;
  always @(posedge aclk) begin
    if (reset_parse_idx) begin
      parse_idx_r <= 0;
      parse_idx_oflow <= 0;
    end else begin
      if (parse_idx_r + parse_idx_incr > 127) parse_idx_oflow <= 1'b1;
      else parse_idx_r <= parse_idx;
    end
  end

  assign parse_idx = reset_parse_idx ? 0 : parse_idx_r + parse_idx_incr;

  always @(posedge aclk) current_byte <= cardinfo[parse_idx];

  always @(posedge aclk) if (latch_key) key <= current_byte;
  always @(posedge aclk) if (latch_len) field_len <= current_byte;

  always @(posedge aclk) begin
    if (latch_len) value_bytes <= 0;
    else if (latch_value) value_bytes <= value_bytes + 1;
  end

  initial sn = '{default: 8'h0};
  always @(posedge aclk) if (latch_value) sn[value_bytes] <= current_byte;

  initial card_sn = '{default: 8'h0};
  always @(posedge aclk) begin
    if (sn_valid || card_sn_vld) card_sn <= sn;
    else begin
      card_sn[0] <= {3'h0, state};
      card_sn[1] <= {4'h0, axil_state};
      card_sn[2] <= {4'h0, parse_state};
    end
  end

  initial card_sn_vld = 1'b0;
  always @(posedge aclk) begin
    if (!aresetn) card_sn_vld <= 1'b0;
    else if (sn_valid) card_sn_vld <= 1'b1;
  end

  always @(posedge aclk) card_sn_len <= field_len-1;

  // Latch error status
  initial begin
    error_boot_timeout = 1'b0;
    error_bad_axil_transaction = 1'b0;
    error_card_info_length = 1'b0;
    error_bad_info_parse = 1'b0;
  end
  always @(posedge aclk) begin
    if (!aresetn) begin
      error_boot_timeout <= 1'b0;
      error_bad_axil_transaction <= 1'b0;
      error_card_info_length <= 1'b0;
      error_bad_info_parse <= 1'b0;
    end else begin
      if (__error_boot_timeout) error_boot_timeout <= 1'b1;
      if (__error_bad_axil_transaction) error_bad_axil_transaction <= 1'b1;
      if (__error_card_info_length) error_card_info_length <= 1'b1;
      if (__error_bad_info_parse) error_bad_info_parse <= 1'b1;
    end
  end

  // AXI-L state machine
  initial axil_state = AXIL_RESET;
  always @(posedge aclk) begin
    if (!aresetn) axil_state <= AXIL_RESET;
    else          axil_state <= nxt_axil_state;
  end

  always_comb begin
    nxt_axil_state = axil_state;
    awvalid = 1'b0;
    wvalid = 1'b0;
    arvalid = 1'b0;
    bready = 1'b0;
    rready = 1'b0;
    case (axil_state)
      AXIL_RESET : begin
        nxt_axil_state = AXIL_IDLE;
      end
      AXIL_IDLE : begin
        if (wr_req) nxt_axil_state = AXIL_AW_W;
        else if (rd_req) nxt_axil_state = AXIL_AR;
      end
      AXIL_AW_W : begin
        awvalid = 1'b1;
        wvalid = 1'b1;
        if (m_axi_ctrl_AWREADY && m_axi_ctrl_WREADY) nxt_axil_state = AXIL_B;
        else if (m_axi_ctrl_AWREADY) nxt_axil_state = AXIL_W;
        else if (m_axi_ctrl_WREADY) nxt_axil_state = AXIL_AW;
      end
      AXIL_AW : begin
        awvalid = 1'b1;
        if (m_axi_ctrl_AWREADY) nxt_axil_state = AXIL_B;
      end
      AXIL_W : begin
        wvalid = 1'b1;
        if (m_axi_ctrl_WREADY) nxt_axil_state = AXIL_B;
      end
      AXIL_B : begin
        bready = 1'b1;
        if (m_axi_ctrl_BVALID) begin
          if (m_axi_ctrl_BRESP == AXIL__RESP_OKAY) nxt_axil_state = AXIL_DONE;
          else                                     nxt_axil_state = AXIL_ERROR;
        end
      end
      AXIL_AR : begin
        arvalid = 1'b1;
        if (m_axi_ctrl_ARREADY) nxt_axil_state = AXIL_R;
      end
      AXIL_R : begin
        rready = 1'b1;
        if (m_axi_ctrl_RVALID) begin
          if (m_axi_ctrl_RRESP == AXIL__RESP_OKAY) nxt_axil_state = AXIL_DONE;
          else                                     nxt_axil_state = AXIL_ERROR;
        end
      end
      AXIL_DONE : begin
        nxt_axil_state = AXIL_IDLE;
      end
      AXIL_ERROR : begin
        nxt_axil_state = AXIL_IDLE;
      end
    endcase
  end

  always @(posedge aclk) if (m_axi_ctrl_RVALID && rready) rdata <= m_axi_ctrl_RDATA;

  // AXI-L mux
  initial done = 1'b0;
  always @(posedge aclk) begin
    if (state == RESET) done <= 1'b0;
    else if (state == DONE) done <= 1'b1;
  end 

  assign m_axi_ctrl_AWVALID = done ? s_axi_ctrl_AWVALID : awvalid;
  assign m_axi_ctrl_AWADDR  = done ? s_axi_ctrl_AWADDR  : awaddr;
  assign m_axi_ctrl_AWPROT  = done ? s_axi_ctrl_AWPROT  : '0;
  assign m_axi_ctrl_WVALID  = done ? s_axi_ctrl_WVALID  : wvalid;
  assign m_axi_ctrl_WDATA   = done ? s_axi_ctrl_WDATA   : wdata;
  assign m_axi_ctrl_WSTRB   = done ? s_axi_ctrl_WSTRB   : '1;
  assign m_axi_ctrl_BREADY  = done ? s_axi_ctrl_BREADY  : bready;
  assign m_axi_ctrl_ARVALID = done ? s_axi_ctrl_ARVALID : arvalid;
  assign m_axi_ctrl_ARADDR  = done ? s_axi_ctrl_ARADDR  : araddr;
  assign m_axi_ctrl_ARPROT  = done ? s_axi_ctrl_ARPROT  : '0;
  assign m_axi_ctrl_RREADY  = done ? s_axi_ctrl_RREADY  : rready;

  assign s_axi_ctrl_AWREADY = done ? m_axi_ctrl_AWREADY : 1'b0;
  assign s_axi_ctrl_WREADY  = done ? m_axi_ctrl_WREADY  : 1'b0;
  assign s_axi_ctrl_BVALID  = done ? m_axi_ctrl_BVALID  : 1'b0;
  assign s_axi_ctrl_BRESP   = done ? m_axi_ctrl_BRESP   : '0;
  assign s_axi_ctrl_ARREADY = done ? m_axi_ctrl_ARREADY : 1'b0;
  assign s_axi_ctrl_RVALID  = done ? m_axi_ctrl_RVALID  : 1'b0;
  assign s_axi_ctrl_RRESP   = done ? m_axi_ctrl_RRESP   : '0;
  assign s_axi_ctrl_RDATA   = done ? m_axi_ctrl_RDATA   : '0;

endmodule