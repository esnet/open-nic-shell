module qdma_pci_cfg_ext_vpd #(
    parameter int         NUM_PHYS_FUNC   = 2,
    parameter logic [7:0] CFG_EXT_NXT_CAP = 8'h0 // Next capability pointer
) (
    input  logic             aclk,
    input  logic             aresetn,
    input  logic             cfg_ext_read_received,
    input  logic             cfg_ext_write_received,
    input  logic [9:0]       cfg_ext_register_number,
    input  logic [7:0]       cfg_ext_function_number,
    input  logic [31:0]      cfg_ext_write_data,
    input  logic [3:0]       cfg_ext_write_byte_enable,
    output logic [31:0]      cfg_ext_read_data,
    output logic             cfg_ext_read_data_valid,

    input  logic             vpd_clk,
    input  logic             vpd_srst,
    output logic             vpd_req,
    output logic             vpd_wr_rd_n,
    output logic [14:0]      vpd_addr,
    output logic [7:0]       vpd_wr_data,
    input  logic [7:0]       vpd_rd_data,
    input  logic             vpd_rd_vld
);
    // Parameters
    localparam int CFG_EXT_CAP_ID__VPD = 8'h03;
    localparam int CFG_EXT_LEGACY_LO_DWORD_IDX = 10'h0B0 >> 2;
    localparam int CFG_EXT_LEGACY_HI_DWORD_IDX = 10'h0BF >> 2;

    localparam int CFG_EXT_REGISTER__VPD_CTRL = CFG_EXT_LEGACY_LO_DWORD_IDX;
    localparam int CFG_EXT_REGISTER__VPD_DATA = CFG_EXT_REGISTER__VPD_CTRL + 1;

    localparam int VPD_ADDR_WID = 15;

    localparam int FUNC_SEL_WID = $clog2(NUM_PHYS_FUNC);

    // Typedefs
    typedef enum logic [3:0] {
        VPD_RESET,
        VPD_IDLE,
        VPD_WR_REQ,
        VPD_WR,
        VPD_WR_DONE,
        VPD_RD_REQ,
        VPD_RD,
        VPD_RD_WAIT,
        VPD_RD_NXT,
        VPD_RD_DONE
    } vpd_state_t;

    typedef enum logic [1:0] {
        ARB_RESET,
        ARB_IDLE,
        ARB_BUSY
    } arb_state_t;

    typedef struct packed {
        logic                    wr_rd_n;
        logic [VPD_ADDR_WID-1:0] addr;
        logic [7:0]              wr_data;
    } vpd_req_t;

    typedef struct packed {
        logic [7:0]              rd_data;
    } vpd_resp_t;

    // Signals
    logic cfg_register_in_range;
    logic cfg_read;
    logic cfg_write;
    struct packed {logic flag; logic[VPD_ADDR_WID-1:0] addr; logic[7:0] NXT_CAP; logic[7:0] CAP_ID;} vpd_ctrl_reg [NUM_PHYS_FUNC];
    logic [3:0][7:0] vpd_data_reg [NUM_PHYS_FUNC];

    logic [FUNC_SEL_WID-1:0] func_sel;

    logic                    vpd_rdy;
    logic                    vpd_req_func    [NUM_PHYS_FUNC];
    logic                    vpd_wr_func     [NUM_PHYS_FUNC];
    logic                    vpd_rd_func     [NUM_PHYS_FUNC];
    logic [VPD_ADDR_WID-1:0] vpd_addr_func   [NUM_PHYS_FUNC];
    logic [7:0]              vpd_wr_data_func[NUM_PHYS_FUNC];
    logic                    vpd_done_func   [NUM_PHYS_FUNC];

    logic             __vpd_req;
    vpd_req_t         __vpd_req_data;
    vpd_req_t         vpd_req_data;

    vpd_resp_t        vpd_resp_data;
    vpd_resp_t        __vpd_resp_data;
    logic             __vpd_rd_vld;
    logic [7:0]       __vpd_rd_data;

    arb_state_t       arb_state;
    arb_state_t       nxt_arb_state;

    assign cfg_register_in_range = (cfg_ext_register_number >= CFG_EXT_LEGACY_LO_DWORD_IDX) && (cfg_ext_register_number <= CFG_EXT_LEGACY_HI_DWORD_IDX);
    assign cfg_read  = cfg_ext_read_received  && cfg_register_in_range;
    assign cfg_write = cfg_ext_write_received && cfg_register_in_range;

    // Config register read
    initial cfg_ext_read_data_valid = 1'b0;
    always @(posedge aclk) begin
        if (!aresetn)      cfg_ext_read_data_valid <= 1'b0;
        else if (cfg_read) cfg_ext_read_data_valid <= 1'b1;
        else               cfg_ext_read_data_valid <= 1'b0;
    end

    always_ff @(posedge aclk) begin
        if (cfg_read) begin
            if (cfg_ext_function_number < NUM_PHYS_FUNC) begin
                case (cfg_ext_register_number)
                    CFG_EXT_REGISTER__VPD_CTRL : cfg_ext_read_data <= vpd_ctrl_reg[cfg_ext_function_number[FUNC_SEL_WID-1:0]];
                    CFG_EXT_REGISTER__VPD_DATA : cfg_ext_read_data <= vpd_data_reg[cfg_ext_function_number[FUNC_SEL_WID-1:0]];
                    default :                    cfg_ext_read_data <= 0;
                endcase
            end else cfg_ext_read_data <= 0;
        end
    end

    generate
        for (genvar g_func = 0; g_func < NUM_PHYS_FUNC; g_func++) begin : g__func
            // (Local) parameters
            vpd_state_t              vpd_state;
            vpd_state_t              nxt_vpd_state;

            logic                    latch_vpd_meta;
            logic                    clear_vpd_flag;
            logic                    set_vpd_flag;

            logic [1:0]              byte_idx;
            logic                    reset_byte_idx;
            logic                    inc_byte_idx;

            logic                    vpd_flag;
            logic                    vpd_arb_req;
            logic                    vpd_arb_grant;
            logic [VPD_ADDR_WID-1:0] vpd_base_addr;
            logic                    vpd_wr;
            logic [3:0]              vpd_wr_byte_en;
            logic                    vpd_rd;
            logic                    vpd_done;

            // VPD capability/control register
            assign vpd_ctrl_reg[g_func].flag    = vpd_flag;
            assign vpd_ctrl_reg[g_func].addr    = vpd_base_addr;
            assign vpd_ctrl_reg[g_func].NXT_CAP = CFG_EXT_NXT_CAP;
            assign vpd_ctrl_reg[g_func].CAP_ID  = CFG_EXT_CAP_ID__VPD;

            // VPD write/read FSM
            initial vpd_state = VPD_RESET;
            always @(posedge aclk) begin
                if (!aresetn) vpd_state <= VPD_RESET;
                else          vpd_state <= nxt_vpd_state;
            end

            always_comb begin
                nxt_vpd_state = vpd_state;
                reset_byte_idx = 1'b0;
                inc_byte_idx = 1'b0;
                vpd_arb_req = 1'b0;
                set_vpd_flag = 1'b0;
                clear_vpd_flag = 1'b0;
                latch_vpd_meta = 1'b0;
                vpd_wr = 1'b0;
                vpd_rd = 1'b0;
                vpd_done = 1'b0;
                case (vpd_state)
                    VPD_RESET : begin
                        clear_vpd_flag = 1'b1;
                        nxt_vpd_state = VPD_IDLE;
                    end
                    VPD_IDLE : begin
                        reset_byte_idx = 1'b1;
                        if (cfg_write && cfg_ext_register_number == CFG_EXT_REGISTER__VPD_CTRL && cfg_ext_function_number == g_func) begin
                            latch_vpd_meta = 1'b1;
                            if (cfg_ext_write_data[31]) begin
                                set_vpd_flag = 1'b1;
                                nxt_vpd_state = VPD_WR_REQ;
                            end else begin
                                clear_vpd_flag = 1'b1;
                                nxt_vpd_state = VPD_RD_REQ;
                            end
                        end
                    end
                    VPD_WR_REQ : begin
                        vpd_arb_req = 1'b1;
                        if (vpd_arb_grant) nxt_vpd_state = VPD_WR;
                    end
                    VPD_WR : begin
                        inc_byte_idx = 1'b1;
                        vpd_wr = 1'b1;
                        if (byte_idx == 3) nxt_vpd_state = VPD_WR_DONE;
                    end
                    VPD_WR_DONE : begin
                        vpd_done = 1'b1;
                        clear_vpd_flag = 1'b1;
                        nxt_vpd_state = VPD_IDLE;
                    end
                    VPD_RD_REQ : begin
                        vpd_arb_req = 1'b1;
                        if (vpd_arb_grant) nxt_vpd_state = VPD_RD;
                    end
                    VPD_RD : begin
                      vpd_rd = 1'b1;
                      nxt_vpd_state = VPD_RD_WAIT;
                    end
                    VPD_RD_WAIT : begin
                      if (__vpd_rd_vld) begin
                        if (byte_idx == 3) nxt_vpd_state = VPD_RD_DONE;
                        else               nxt_vpd_state = VPD_RD_NXT;
                      end
                    end
                    VPD_RD_NXT : begin
                        inc_byte_idx = 1'b1;
                        nxt_vpd_state = VPD_RD;
                    end
                    VPD_RD_DONE : begin
                      vpd_done = 1'b1;
                      set_vpd_flag = 1'b1;
                      nxt_vpd_state = VPD_IDLE;
                    end
                    default : begin
                      nxt_vpd_state = VPD_RESET;
                    end
              endcase
            end

            always_ff @(posedge aclk) begin
                if (latch_vpd_meta) begin
                    vpd_base_addr <= cfg_ext_write_data[30:16];
                    vpd_wr_byte_en <= cfg_ext_write_byte_enable;
                end
            end

            initial vpd_flag = 1'b0;
            always @(posedge aclk) begin
                if (!aresetn)            vpd_flag <= 1'b0;
                else if (clear_vpd_flag) vpd_flag <= 1'b0;
                else if (set_vpd_flag)   vpd_flag <= 1'b1;
            end

            initial byte_idx = 0;
            always @(posedge aclk) begin
              if (reset_byte_idx) byte_idx <= 0;
              else if (inc_byte_idx) byte_idx <= byte_idx + 1;
            end

            initial vpd_data_reg[g_func] = 0;
            always @(posedge aclk) begin
              if (cfg_write && cfg_ext_register_number == CFG_EXT_REGISTER__VPD_DATA && cfg_ext_function_number == g_func) begin
                  for (int b = 0; b < 4; b++) begin
                      if (cfg_ext_write_byte_enable[b])
                          vpd_data_reg[g_func][b] <= cfg_ext_write_data[b*8 +: 8];
                  end
              end else if (vpd_state == VPD_RD_WAIT && __vpd_rd_vld) begin
                  vpd_data_reg[g_func][byte_idx] <= __vpd_rd_data;
              end
            end

            assign vpd_req_func    [g_func] = vpd_arb_req;
            assign vpd_arb_grant            = vpd_rdy && (func_sel == g_func);
            assign vpd_wr_func     [g_func] = vpd_wr && vpd_wr_byte_en[byte_idx];
            assign vpd_rd_func     [g_func] = vpd_rd;
            assign vpd_addr_func   [g_func] = vpd_base_addr + byte_idx;
            assign vpd_wr_data_func[g_func] = vpd_data_reg[byte_idx];
            assign vpd_done_func   [g_func] = vpd_done;

        end : g__func
    endgenerate

    // Arbitrate access to VPD read/write interface
    initial func_sel = 0;
    always @(posedge aclk) begin
        if (vpd_rdy && !vpd_req_func[func_sel]) func_sel <= func_sel < NUM_PHYS_FUNC-1 ? func_sel + 1 : 0;
    end

    initial arb_state = ARB_RESET;
    always @(posedge aclk) begin
        if (!aresetn) arb_state <= ARB_RESET;
        else          arb_state <= nxt_arb_state;
    end

    always_comb begin
        nxt_arb_state = arb_state;
        vpd_rdy = 1'b0;
        case(arb_state)
            ARB_RESET : begin
                nxt_arb_state = ARB_IDLE;
            end
            ARB_IDLE : begin
                vpd_rdy = 1'b1;
                if (vpd_req_func[func_sel]) nxt_arb_state = ARB_BUSY;
            end
            ARB_BUSY : begin
                if (vpd_done_func[func_sel]) nxt_arb_state = ARB_IDLE;
            end
            default : begin
                nxt_arb_state = ARB_RESET;
            end
        endcase
    end

    // Cross VPD request interface from aclk to vpd_clk domains
    // -- Pack bus
    assign __vpd_req = vpd_wr_func[func_sel] || vpd_rd_func[func_sel];
    assign __vpd_req_data.wr_rd_n = vpd_wr_func[func_sel];
    assign __vpd_req_data.addr    = vpd_addr_func   [func_sel];
    assign __vpd_req_data.wr_data = vpd_wr_data_func[func_sel];
    // -- Synchronizer
    level_trigger_cdc #(
        .DATA_W ($bits(vpd_req_t)),
        .FIFO_DEPTH  ( 16 )
    ) level_trigger_cdc_inst__req (
        .src_valid ( __vpd_req ),
        .src_data  ( __vpd_req_data ),
        .src_miss  ( ),
        .dst_valid ( vpd_req ),
        .dst_data  ( vpd_req_data ),
        .src_clk   ( aclk ),
        .dst_clk   ( vpd_clk ),
        .src_rstn  ( aresetn )
    );
    // -- Unpack bus
    assign vpd_wr_rd_n = vpd_req_data.wr_rd_n;
    assign vpd_addr    = vpd_req_data.addr;
    assign vpd_wr_data = vpd_req_data.wr_data;

    // Cross VPD response interface from vpd_clk to aclk domains
    // -- Pack bus
    assign vpd_resp_data.rd_data = vpd_rd_data;
    // -- Synchronizer
    level_trigger_cdc #(
        .DATA_W ($bits(vpd_resp_t)),
        .FIFO_DEPTH  ( 16 )
    ) level_trigger_cdc_inst__resp (
        .src_valid ( vpd_rd_vld ),
        .src_data  ( vpd_resp_data ),
        .src_miss  ( ),
        .dst_valid ( __vpd_rd_vld ),
        .dst_data  ( __vpd_resp_data ),
        .src_clk   ( vpd_clk ),
        .dst_clk   ( aclk ),
        .src_rstn  ( !vpd_srst )
    );
    // --Unpack bus
    assign __vpd_rd_data = __vpd_resp_data.rd_data;

endmodule : qdma_pci_cfg_ext_vpd