// Stub plugin: all box signals are tied off.
// Terminates the box AXI-Lite interface. Writes are accepted and discarded;
// reads return zero. All responses are OKAY.
`timescale 1ns/1ps
module box_322mhz_address_map (
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

  input         aclk,
  input         aresetn
);

  reg bvalid;
  reg rvalid;

  wire wr_accept = s_axil_awvalid && s_axil_wvalid && !bvalid;
  wire rd_accept = s_axil_arvalid && !rvalid;

  always @(posedge aclk) begin
    if (!aresetn) begin
      bvalid <= 1'b0;
      rvalid <= 1'b0;
    end else begin
      if (wr_accept)                    bvalid <= 1'b1;
      else if (s_axil_bready)           bvalid <= 1'b0;

      if (rd_accept)                    rvalid <= 1'b1;
      else if (s_axil_rready)           rvalid <= 1'b0;
    end
  end

  assign s_axil_awready = wr_accept;
  assign s_axil_wready  = wr_accept;
  assign s_axil_bvalid  = bvalid;
  assign s_axil_bresp   = 2'b00;
  assign s_axil_arready = rd_accept;
  assign s_axil_rvalid  = rvalid;
  assign s_axil_rdata   = 32'h0;
  assign s_axil_rresp   = 2'b00;

endmodule: box_322mhz_address_map
