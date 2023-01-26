// *************************************************************************
//
// Copyright 2020 Xilinx, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// *************************************************************************
// Address range: 0x0000 - 0x0FFF
// Address width: 12-bit
//
// Register description
// -----------------------------------------------------------------------------
//  Address | Mode |          Description
// -----------------------------------------------------------------------------
//   0x000  |  RO  | Build timestamp register
// -----------------------------------------------------------------------------
//   0x004  |  WO  | System reset register
// -----------------------------------------------------------------------------
//   0x008  |  RO  | System status register
// -----------------------------------------------------------------------------
//   0x00C  |  WO  | Shell reset register
// -----------------------------------------------------------------------------
//   0x010  |  RO  | Shell status register
// -----------------------------------------------------------------------------
//   0x014  |  WO  | User reset register
// -----------------------------------------------------------------------------
//   0x018  |  RO  | User status register
// -----------------------------------------------------------------------------
//   0x01C  |  RO  | Xilinx usr_access register
// -----------------------------------------------------------------------------
//   0x020  |  RO  | Xilinx dna register
//     |    |      |
//   0x02B  |      |
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module system_config_register #(
  parameter [31:0] BUILD_TIMESTAMP = 32'h01010000
) (
  input         s_axil_awvalid,
  input  [31:0] s_axil_awaddr,
  output        s_axil_awready,
  input         s_axil_wvalid,
  input  [31:0] s_axil_wdata,
  output        s_axil_wready,
  output        s_axil_bvalid,
  output  [1:0] s_axil_bresp,
  input         s_axil_bready,
  input         s_axil_arvalid,
  input  [31:0] s_axil_araddr,
  output        s_axil_arready,
  output        s_axil_rvalid,
  output [31:0] s_axil_rdata,
  output  [1:0] s_axil_rresp,
  input         s_axil_rready,

  output [31:0] shell_rstn,
  input  [31:0] shell_rst_done,
  output [31:0] user_rstn,
  input  [31:0] user_rst_done,

  input         aclk,
  input         aresetn
);

  localparam C_ADDR_W = 12;

  // Register address
  localparam REG_BUILD_TIMESTAMP = 12'h000;
  localparam REG_SYSTEM_RST      = 12'h004;
  localparam REG_SYSTEM_STATUS   = 12'h008;
  localparam REG_SHELL_RST       = 12'h00C;
  localparam REG_SHELL_STATUS    = 12'h010;
  localparam REG_USER_RST        = 12'h014;
  localparam REG_USER_STATUS     = 12'h018;
  localparam REG_USR_ACCESS      = 12'h01c;  // xilinx usr_access register (32b).
  localparam REG_DNA_0           = 12'h020;  // xilinx dna register (96b).
  localparam REG_DNA_1           = 12'h024;
  localparam REG_DNA_2           = 12'h028;

  // Regsiters
  reg          [31:0] reg_build_timestamp;
  reg                 reg_system_rst;
  reg                 reg_system_status;
  reg          [31:0] reg_shell_rst;
  reg          [31:0] reg_shell_status;
  reg          [31:0] reg_user_rst;
  reg          [31:0] reg_user_status;

  wire         [31:0] reg_usr_access;  // xilinx usr_access register.
  reg          [95:0] reg_dna;         // xilinx dna register.

  reg          [31:0] shell_rst_last;
  reg          [31:0] user_rst_last;
  reg                 system_rst_last;
  wire                system_rst;
  wire                system_rst_done;
  
  wire                reg_en;
  wire                reg_we;
  wire [C_ADDR_W-1:0] reg_addr;
  wire         [31:0] reg_din;
  reg          [31:0] reg_dout;

  axi_lite_register #(
    .CLOCKING_MODE ("common_clock"),
    .ADDR_W        (C_ADDR_W),
    .DATA_W        (32)
  ) axil_reg_inst (
    .s_axil_awvalid (s_axil_awvalid),
    .s_axil_awaddr  (s_axil_awaddr),
    .s_axil_awready (s_axil_awready),
    .s_axil_wvalid  (s_axil_wvalid),
    .s_axil_wdata   (s_axil_wdata),
    .s_axil_wready  (s_axil_wready),
    .s_axil_bvalid  (s_axil_bvalid),
    .s_axil_bresp   (s_axil_bresp),
    .s_axil_bready  (s_axil_bready),
    .s_axil_arvalid (s_axil_arvalid),
    .s_axil_araddr  (s_axil_araddr),
    .s_axil_arready (s_axil_arready),
    .s_axil_rvalid  (s_axil_rvalid),
    .s_axil_rdata   (s_axil_rdata),
    .s_axil_rresp   (s_axil_rresp),
    .s_axil_rready  (s_axil_rready),

    .reg_en         (reg_en),
    .reg_we         (reg_we),
    .reg_addr       (reg_addr),
    .reg_din        (reg_din),
    .reg_dout       (reg_dout),

    .axil_aclk      (aclk),
    .axil_aresetn   (aresetn),
    .reg_clk        (aclk),
    .reg_rstn       (aresetn)
  );

  always @(posedge aclk) begin
    if (~aresetn) begin
      reg_dout <= 0;
    end
    else if (reg_en && ~reg_we) begin
      case (reg_addr)
        REG_BUILD_TIMESTAMP: begin
          reg_dout <= BUILD_TIMESTAMP;
        end
        REG_SYSTEM_STATUS: begin
          reg_dout <= {31'b0, reg_system_status};
        end
        REG_SHELL_STATUS: begin
          reg_dout <= reg_shell_status;
        end
        REG_USER_STATUS: begin
          reg_dout <= reg_user_status;
        end
        REG_USR_ACCESS: begin
          reg_dout <= reg_usr_access;
        end
        REG_DNA_0: begin
          reg_dout <= reg_dna[31:0];
        end
        REG_DNA_1: begin
          reg_dout <= reg_dna[63:32];
        end
        REG_DNA_2: begin
          reg_dout <= reg_dna[95:64];
        end
        default: begin
          reg_dout <= 32'hDEADBEEF;
        end
      endcase
    end
  end

  always @(posedge aclk) begin
    if (~aresetn) begin
      shell_rst_last  <= 0;
      user_rst_last   <= 0;
      system_rst_last <= 1'b0;
    end
    else begin
      shell_rst_last  <= reg_shell_rst;
      user_rst_last   <= reg_user_rst;
      system_rst_last <= reg_system_rst;
    end
  end

  // Submodule resets are triggered either by writing to the reset registers, or
  // through power-up reset.  These reset signals are active-low and valid for a
  // single cycle.
  generate for (genvar ii = 0; ii < 32; ii = ii + 1) begin
    assign shell_rstn[ii] = ~(system_rst || (~shell_rst_last[ii] && reg_shell_rst[ii]));
    assign user_rstn[ii]  = ~(system_rst || (~user_rst_last[ii] && reg_user_rst[ii]));
  end
  endgenerate

  assign system_rst      = ~system_rst_last && reg_system_rst;
  assign system_rst_done = (&shell_rst_done) && (&user_rst_done);

  // System reset register (write-only)
  //
  // Writing to this register initiates a system-level reset, which lasts until
  // all the submodules are out of reset.  A system-level reset is also done on
  // power up.
  always @(posedge aclk) begin
    if (~aresetn) begin
      reg_system_rst <= 1'b1;
    end
    else if (reg_en && reg_we && reg_addr == REG_SYSTEM_RST) begin
      reg_system_rst <= 1'b1;
    end
    else if (system_rst_done) begin
      reg_system_rst <= 0;
    end
  end

  // Shell reset register (write-only)
  //
  // 31:3  - reserved
  // 2     - reset for the CMAC subsystem CMAC1
  // 1     - reset for the CMAC subsystem CMAC0
  // 0     - reset for the QDMA subsystem
  // 
  // Writing 1 to a bit of this register initiates a submodule-level reset in
  // the shell logic, which lasts until the corresponding submodule is out of
  // reset.  Mapping between bits and submodules are as follows.
  generate for (genvar ii = 0; ii < 32; ii = ii + 1) begin
    always @(posedge aclk) begin
      if (~aresetn) begin
        reg_shell_rst[ii] <= 1'b0;
      end
      else if (reg_en && reg_we && reg_addr == REG_SHELL_RST && reg_din[ii]) begin
        reg_shell_rst[ii] <= 1'b1;
      end
      else if (shell_rst_done[ii]) begin
        reg_shell_rst[ii] <= 0;
      end
    end
  end
  endgenerate

  // User reset register (write-only)
  //
  // Writing 1 to a bit of this register initiates a submodule-level reset in
  // the user logic, which lasts until the corresponding submodule is out of
  // reset.  Mapping between bits and submodules are determined by how the user
  // logic is connected in the top level.
  generate for (genvar ii = 0; ii < 32; ii = ii + 1) begin
    always @(posedge aclk) begin
      if (~aresetn) begin
        reg_user_rst[ii] <= 1'b0;
      end
      else if (reg_en && reg_we && reg_addr == REG_USER_RST && reg_din[ii]) begin
        reg_user_rst[ii] <= 1'b1;
      end
      else if (user_rst_done[ii]) begin
        reg_user_rst[ii] <= 0;
      end
    end
  end
  endgenerate

  // System status register (read-only)
  // 
  // 31:1  - reserved
  // 0     - system reset done
  // 
  // The register shows the system reset status.
  always @(posedge aclk) begin
    if (~aresetn) begin
      reg_system_status <= 1'b0;
    end
    else if (system_rst) begin
      reg_system_status <= 1'b0;
    end
    else if (system_rst_done) begin
      reg_system_status <= 1'b1;
    end
  end

  // Shell status register (read-only)
  //
  // 31:3  - reserved
  // 2     - CMAC subsystem CMAC1 reset done
  // 1     - CMAC subsystem CMAC0 reset done
  // 0     - QDMA subsystem reset done
  //
  // This register shows the reset status of shell submodules.
  generate for (genvar ii = 0; ii < 32; ii = ii + 1) begin
    always @(posedge aclk) begin
      if (~aresetn) begin
        reg_shell_status[ii] <= 1'b0;
      end
      else if (~shell_rstn[ii]) begin
        reg_shell_status[ii] <= 1'b0;
      end
      else if (shell_rst_done[ii]) begin
        reg_shell_status[ii] <= 1'b1;
      end
    end
  end
  endgenerate

  // User status register (read-only)
  //
  // This register shows the reset status of user submodules.  Mapping between
  // bits and submodules are determined by how the user logic is connected in
  // the top level.
  generate for (genvar ii = 0; ii < 32; ii = ii + 1) begin
    always @(posedge aclk) begin
      if (~aresetn) begin
        reg_user_status[ii] <= 1'b0;
      end
      else if (~user_rstn[ii]) begin
        reg_user_status[ii] <= 1'b0;
      end
      else if (user_rst_done[ii]) begin
        reg_user_status[ii] <= 1'b1;
      end
    end
  end
  endgenerate

// ---- xilinx usr_access and dna register instantiations - begin ---

   USR_ACCESSE2 USR_ACCESSE2_0 (.CFGCLK(), .DATA (reg_usr_access), .DATAVALID());

   wire dna_dout;

   DNA_PORTE2 #(.SIM_DNA_VALUE(96'h6666_5555_4444_3333_2222_1111)) DNA_PORTE2_0
      (.CLK(aclk), .READ(!aresetn), .SHIFT(aresetn), .DIN(1'b0), .DOUT(dna_dout));

   reg [6:0] dna_cnt;

   always @(posedge aclk) begin
      if (!aresetn) begin
         dna_cnt <= 7'd96;
         reg_dna <= 0;
      end else if (dna_cnt > 0) begin
         dna_cnt <= dna_cnt-1;
         reg_dna <= {dna_dout, reg_dna[95:1]};
      end
   end

// ---- xilinx usr_access and dna register logic - end ---


endmodule: system_config_register
