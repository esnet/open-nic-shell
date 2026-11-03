// Stub plugin: all box signals are tied off.
box_250mhz_address_map address_map_inst (
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

  .aclk           (axil_aclk),
  .aresetn        (internal_box_rstn)
);
