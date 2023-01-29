# *************************************************************************
#
# Copyright 2023 Advanced Micro Devices
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

##################################################################
# CREATE IP c2h_axis_interconnect_1
##################################################################

set c2h_axis_interconnect_1 c2h_axis_interconnect_1
create_ip -name axis_interconnect -vendor xilinx.com -library ip -module_name c2h_axis_interconnect_1 -dir ${ip_build_dir}

# User Parameters
set_property -dict [list \
  CONFIG.C_M00_AXIS_BASETDEST {0x00000000} \
  CONFIG.C_M00_AXIS_HIGHTDEST {0x00000000} \
  CONFIG.C_M00_AXIS_IS_ACLK_ASYNC {1} \
  CONFIG.C_M00_AXIS_REG_CONFIG {1} \
  CONFIG.C_M01_AXIS_BASETDEST {0x00000001} \
  CONFIG.C_M01_AXIS_HIGHTDEST {0x00000001} \
  CONFIG.C_M01_AXIS_IS_ACLK_ASYNC {1} \
  CONFIG.C_M01_AXIS_REG_CONFIG {1} \
  CONFIG.C_NUM_MI_SLOTS {2} \
  CONFIG.C_NUM_SI_SLOTS {1} \
  CONFIG.C_S00_AXIS_IS_ACLK_ASYNC {1} \
  CONFIG.C_S00_AXIS_REG_CONFIG {1} \
  CONFIG.C_S01_AXIS_IS_ACLK_ASYNC {1} \
  CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {1} \
  CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} \
  CONFIG.C_SWITCH_TDEST_WIDTH {1} \
  CONFIG.HAS_TDEST {true} \
  CONFIG.HAS_TID {false} \
  CONFIG.HAS_TKEEP {false} \
  CONFIG.HAS_TSTRB {false} \
  CONFIG.HAS_TUSER {true} \
  CONFIG.M00_AXIS_TDATA_NUM_BYTES {64} \
  CONFIG.M00_S01_CONNECTIVITY {false} \
  CONFIG.M01_AXIS_TDATA_NUM_BYTES {64} \
  CONFIG.M01_S00_CONNECTIVITY {true} \
  CONFIG.S00_AXIS_TDATA_NUM_BYTES {64} \
  CONFIG.S01_AXIS_TDATA_NUM_BYTES {64} \
  CONFIG.SWITCH_PACKET_MODE {false} \
  CONFIG.SWITCH_TDATA_NUM_BYTES {64} \
  CONFIG.SWITCH_TUSER_BITS_PER_BYTE {2} \
] [get_ips c2h_axis_interconnect_1]

# Runtime Parameters
#set_property -dict { 
#  GENERATE_SYNTH_CHECKPOINT {1}
#} $c2h_axis_interconnect_1

##################################################################

