# *************************************************************************
#
# Copyright 2023 Advanced Micro Devices
# Copyright 2020 Xilinx, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# *************************************************************************
set ips {
    qdma_no_sriov
    qdma_subsystem_clk_div
    qdma_subsystem_axi_cdc
    qdma_subsystem_axi_crossbar
    qdma_subsystem_c2h_ecc
}
if {$board == "sn1022"} {
    lappend ips "qdma_no_sriov_arm"
    lappend ips "c2h_axis_interconnect_1"
    lappend ips "h2c_axis_interconnect_1"
    lappend ips "cpl_axis_interconnect_1"
    lappend ips "vio_0_1"
#    lappend ips "cms_qspi_sn1022"
}
