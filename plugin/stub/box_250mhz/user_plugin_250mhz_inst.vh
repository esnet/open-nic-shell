// Stub plugin: all box signals are tied off.
// All module resets complete immediately.
assign mod_rst_done = {16{1'b1}};

// QDMA H2C/C2H interfaces are terminated by box_250mhz when USE_PHYS_FUNC == 0.
generate if (USE_PHYS_FUNC != 0) begin
  assign s_axis_qdma_h2c_tready          = {NUM_PHYS_FUNC*NUM_QDMA{1'b1}};

  assign m_axis_qdma_c2h_tvalid          = 0;
  assign m_axis_qdma_c2h_tdata           = 0;
  assign m_axis_qdma_c2h_tkeep           = 0;
  assign m_axis_qdma_c2h_tlast           = 0;
  assign m_axis_qdma_c2h_tuser_size      = 0;
  assign m_axis_qdma_c2h_tuser_src       = 0;
  assign m_axis_qdma_c2h_tuser_dst       = 0;
  assign m_axis_qdma_c2h_tuser_qid_valid = 0;
  assign m_axis_qdma_c2h_tuser_qid       = 0;
end
endgenerate

assign m_axis_adap_tx_250mhz_tvalid     = 0;
assign m_axis_adap_tx_250mhz_tdata      = 0;
assign m_axis_adap_tx_250mhz_tkeep      = 0;
assign m_axis_adap_tx_250mhz_tlast      = 0;
assign m_axis_adap_tx_250mhz_tuser_size = 0;
assign m_axis_adap_tx_250mhz_tuser_src  = 0;
assign m_axis_adap_tx_250mhz_tuser_dst  = 0;

assign s_axis_adap_rx_250mhz_tready     = {NUM_CMAC_PORT{1'b1}};
