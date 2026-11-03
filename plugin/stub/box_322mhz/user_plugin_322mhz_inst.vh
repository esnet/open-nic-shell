// Stub plugin: all box signals are tied off.
// All module resets complete immediately.
assign mod_rst_done = {8{1'b1}};

assign s_axis_adap_tx_322mhz_tready         = {NUM_CMAC_PORT{1'b1}};

assign m_axis_adap_rx_322mhz_tvalid         = 0;
assign m_axis_adap_rx_322mhz_tdata          = 0;
assign m_axis_adap_rx_322mhz_tkeep          = 0;
assign m_axis_adap_rx_322mhz_tlast          = 0;
assign m_axis_adap_rx_322mhz_tuser_err      = 0;
assign m_axis_adap_rx_322mhz_tuser_qid_valid = 0;
assign m_axis_adap_rx_322mhz_tuser_qid      = 0;

assign m_axis_cmac_tx_tvalid                = 0;
assign m_axis_cmac_tx_tdata                 = 0;
assign m_axis_cmac_tx_tkeep                 = 0;
assign m_axis_cmac_tx_tlast                 = 0;
assign m_axis_cmac_tx_tuser_err             = 0;
