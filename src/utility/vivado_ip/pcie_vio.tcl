set module_name pcie_vio

create_ip -name vio -vendor xilinx.com -library ip -module_name $module_name -dir ${ip_build_dir}

set_property -dict {
    CONFIG.C_NUM_PROBE_IN {3}
    CONFIG.C_NUM_PROBE_OUT {1}
    CONFIG.C_PROBE_IN0_WIDTH {1}
    CONFIG.C_PROBE_IN1_WIDTH {1}
    CONFIG.C_PROBE_IN2_WIDTH {1}
    CONFIG.C_PROBE_OUT0_WIDTH {1}
} [get_ips $module_name]
