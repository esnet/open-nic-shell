module qdma_pcie_ext_cfg_vpd #(
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

  input  logic             card_sn_vld,
  input  logic [0:11][7:0] card_sn
);
  // Parameters
  localparam int CFG_EXT_CAP_ID__VPD = 8'h03;
  localparam int CFG_EXT_LEGACY_LO_DWORD_IDX = 10'h0B0 >> 2;
  localparam int CFG_EXT_LEGACY_HI_DWORD_IDX = 10'h0BF >> 2;

  localparam int CFG_EXT_REGISTER__VPD_CTRL = CFG_EXT_LEGACY_LO_DWORD_IDX;
  localparam int CFG_EXT_REGISTER__VPD_DATA = CFG_EXT_REGISTER__VPD_CTRL + 1;

  localparam int VPD_ADDR_WID = 15;
  localparam int VPD_BYTES = 40;

  // Typedefs
  typedef enum logic [2:0] {
    VPD_RESET,
    VPD_IDLE,
    VPD_WR,
    VPD_RD,
    VPD_RD_WAIT,
    VPD_RD_ACK
  } vpd_state_t;

  // Signals
  logic cfg_register_in_range;
  logic cfg_read;
  logic cfg_write;
  struct packed {logic flag; logic[VPD_ADDR_WID-1:0] addr; logic[7:0] NXT_CAP; logic[7:0] CAP_ID;} vpd_ctrl_reg;
  logic [3:0][7:0] vpd_data_reg;

  vpd_state_t              vpd_state;
  vpd_state_t              nxt_vpd_state;
  logic                    latch_vpd_addr;

  logic                    vpd_status;
  logic [VPD_ADDR_WID-1:0] vpd_addr;
  logic                    vpd_wr;
  logic                    vpd_rd;
  logic                    vpd_rd_ack;
  logic [3:0][7:0]         vpd_rd_data;

  logic [0:11][7:0]        __card_sn;
  logic [7:0]              fixed_ro_chksum;
  logic [7:0]              cn_chksum;
  logic [7:0]              ro_chksum;

  logic [0:VPD_BYTES-1][7:0] VPD;

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

  initial cfg_ext_read_data = 0;
  always_ff @(posedge aclk) begin
    if (cfg_read) begin
      case (cfg_ext_register_number)
        CFG_EXT_REGISTER__VPD_CTRL : cfg_ext_read_data <= vpd_ctrl_reg;
        CFG_EXT_REGISTER__VPD_DATA : cfg_ext_read_data <= vpd_data_reg;
        default :                    cfg_ext_read_data <= 0;
      endcase
    end
  end

  // VPD capability/control register
  assign vpd_ctrl_reg.flag    = vpd_status;
  assign vpd_ctrl_reg.addr    = vpd_addr;
  assign vpd_ctrl_reg.NXT_CAP = CFG_EXT_NXT_CAP;
  assign vpd_ctrl_reg.CAP_ID  = CFG_EXT_CAP_ID__VPD;


  // VPD write/read FSM
  initial vpd_state = VPD_RESET;
  always @(posedge aclk) begin
    if (!aresetn) vpd_state <= VPD_RESET;
    else          vpd_state <= nxt_vpd_state;
  end

  always_comb begin
    nxt_vpd_state = vpd_state;
    vpd_status = 1'b0;
    latch_vpd_addr = 1'b0;
    case (vpd_state)
      VPD_RESET : begin
        nxt_vpd_state = VPD_IDLE;
      end
      VPD_IDLE : begin
        if (cfg_write && cfg_ext_register_number == CFG_EXT_REGISTER__VPD_CTRL) begin
          latch_vpd_addr = 1'b1;
          if (cfg_ext_write_data[31]) nxt_vpd_state = VPD_WR;
          else                        nxt_vpd_state = VPD_RD;
        end
      end
      VPD_WR : begin
        vpd_status = 1'b1;
        vpd_wr = 1'b1;
        nxt_vpd_state = VPD_IDLE;
      end
      VPD_RD : begin
        vpd_rd = 1'b1;
        nxt_vpd_state = VPD_RD_WAIT;
      end
      VPD_RD_WAIT : begin
        if (vpd_rd_ack) nxt_vpd_state = VPD_RD_ACK;
      end
      VPD_RD_ACK : begin
        vpd_status = 1'b1;
        if (cfg_read && cfg_ext_register_number == CFG_EXT_REGISTER__VPD_CTRL) nxt_vpd_state = VPD_IDLE;
      end
      default : begin
        nxt_vpd_state = VPD_RESET;
      end
    endcase
  end

  initial vpd_addr = '0;
  always @(posedge aclk) begin
    if (!aresetn)            vpd_addr <= '0;
    else if (latch_vpd_addr) vpd_addr <= cfg_ext_write_data[30:16];
  end

  initial vpd_data_reg = 0;
  always @(posedge aclk) begin
    if (cfg_write && cfg_ext_register_number == CFG_EXT_REGISTER__VPD_DATA) begin
      for (int i = 0; i < 4; i++) begin
        if (cfg_ext_write_byte_enable[i]) vpd_data_reg[i] <= cfg_ext_write_data[i*8 +: 8];
      end
    end else if (vpd_rd_ack) begin
        vpd_data_reg <= vpd_rd_data;
    end
  end

  always @(posedge aclk) begin
    if (vpd_rd) begin
      for (int i = 0; i < 4; i ++) begin
        if ((vpd_addr + i) > VPD_BYTES-1) vpd_rd_data[i] <= 8'hFF;
        else                              vpd_rd_data[i] <= VPD[vpd_addr + i];
      end
    end
  end

  initial vpd_rd_ack = 1'b0;
  always_ff @(posedge aclk) vpd_rd_ack <= vpd_rd;

  // Card SN
  always @(posedge aclk) begin
    if (card_sn_vld) __card_sn <= card_sn;
    else             __card_sn <= "UNKNOWN SN!!";
  end

  // VPD Data Structure
  assign VPD = {
          8'h82, 8'h0E, 8'h00,  // Large resource tag, ID 0x82, length 0x000E (14B)
            "ESnet SmartNIC",     // ID
          8'h90, 8'h13, 8'h00,  // RO section, ID 0x90, total length 0x0013 (19B)
            "S", "N", 8'h0C,      // SN tag, ID "SN", length 0x0C (12B)
              __card_sn[0], __card_sn[1], __card_sn[2],  __card_sn[3],
              __card_sn[4], __card_sn[5], __card_sn[6],  __card_sn[7],
              __card_sn[8], __card_sn[9], __card_sn[10], __card_sn[11],
            "R", "V", 8'h01, ro_chksum, // RO checksum
          8'h78 // End tag
        };

  assign fixed_ro_chksum = 8'h82 + 8'h0E + 8'h00 +
                           "E" + "S" + "n" + "e" + "t" + " " + "S" + "m" + "a" + "r" + "t" + "N" + "I" +"C" +
                           8'h90 + 8'h13 + 8'h00 +
                           "S" + "N" + 8'h0C +
                           "R" + "V" + 8'h01;
  
  always_comb begin
    cn_chksum = fixed_ro_chksum;
    for (int i = 0; i < 12; i++) begin
      cn_chksum = cn_chksum + __card_sn[i];
    end
  end

  always @(posedge aclk) ro_chksum <= 9'h100 - cn_chksum;

endmodule : qdma_pcie_ext_cfg_vpd