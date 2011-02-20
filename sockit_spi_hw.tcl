################################################################################
#                                                                              #
#  SPI (3 wire, dual, quad) master                                             #
#                                                                              #
#  Copyright (C) 2011  Iztok Jeras                                             #
#                                                                              #
################################################################################
#                                                                              #
#  This script is free hardware: you can redistribute it and/or modify         #
#  it under the terms of the GNU Lesser General Public License                 #
#  as published by the Free Software Foundation, either                        #
#  version 3 of the License, or (at your option) any later version.            #
#                                                                              #
#  This RTL is distributed in the hope that it will be useful,                 #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <http:#www.gnu.org/licenses/>.        #
#                                                                              #
################################################################################

# request TCL package from Altera tools version 10.0
package require -exact sopc 10.0

# module sockit_owm
set_module_property NAME         sockit_spi
set_module_property VERSION      0.5
set_module_property GROUP        "Interface Protocols/Serial"
set_module_property DISPLAY_NAME "SPI (3-wire, dual, quad) master"
set_module_property DESCRIPTION  "SPI (3-wire, dual, quad) master"
set_module_property AUTHOR       "Iztok Jeras"

set_module_property TOP_LEVEL_HDL_FILE           sockit_spi.v
set_module_property TOP_LEVEL_HDL_MODULE         sockit_spi
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE                     true

# callbacks
#set_module_property  VALIDATION_CALLBACK  validation_callback
#set_module_property ELABORATION_CALLBACK elaboration_callback

# documentation links and files
add_documentation_link WEBLINK https://github.com/jeras/sockit_spi
add_documentation_link WEBLINK http://opencores.org/project,sockit_spi
add_documentation_link DATASHEET doc/sockit_spi.pdf

# RTL files
add_file hdl/sockit_spi.v      {SYNTHESIS SIMULATION}
add_file hdl/sockit_spi_xip.v  {SYNTHESIS SIMULATION}
add_file hdl/sockit_spi_fifo.v {SYNTHESIS SIMULATION}

# # parameters
# add_parameter OVD_E BOOLEAN
# set_parameter_property OVD_E DESCRIPTION "Implementation of overdrive enable, disabling it can spare a small amount of logic."
# set_parameter_property OVD_E DEFAULT_VALUE 1
# set_parameter_property OVD_E UNITS None
# set_parameter_property OVD_E AFFECTS_GENERATION false
# set_parameter_property OVD_E HDL_PARAMETER true
# 
# add_parameter CDR_E BOOLEAN
# set_parameter_property CDR_E DESCRIPTION "Implementation of clock divider ratio registers, disabling it can spare a small amount of logic."
# set_parameter_property CDR_E DEFAULT_VALUE 0
# set_parameter_property CDR_E UNITS None
# set_parameter_property CDR_E AFFECTS_GENERATION false
# set_parameter_property CDR_E HDL_PARAMETER true

# add_parameter CDR_N NATURAL
# set_parameter_property CDR_N DERIVED true
# set_parameter_property CDR_N DESCRIPTION "Clock divider ratio for normal mode"
# set_parameter_property CDR_N DISPLAY_NAME CDR_N
# set_parameter_property CDR_N DEFAULT_VALUE 5
# set_parameter_property CDR_N AFFECTS_GENERATION false
# set_parameter_property CDR_N HDL_PARAMETER true

add_parameter XAW INTEGER
set_parameter_property XAW DESCRIPTION "XIP address width (memory size)"
set_parameter_property XAW DEFAULT_VALUE 24
set_parameter_property XAW ALLOWED_RANGES {16:512-kbit 17:1-Mbit 18:2-Mbit 19:4-Mbit 20:8-Mbit 21:16-Mbit 22:32-Mbit 23:64-Mbit 24:128-Mbit 25:256-Mbit}
set_parameter_property XAW AFFECTS_GENERATION false
set_parameter_property XAW AFFECTS_ELABORATION true
set_parameter_property XAW HDL_PARAMETER true

add_parameter SSW INTEGER
set_parameter_property SSW DESCRIPTION "Number of SS_N (slave select) ports"
set_parameter_property SSW DEFAULT_VALUE 1
set_parameter_property SSW ALLOWED_RANGES {1 2 3 4 5 6 7 8}
set_parameter_property SSW UNITS bits
set_parameter_property SSW AFFECTS_GENERATION false
set_parameter_property SSW AFFECTS_ELABORATION true
set_parameter_property SSW HDL_PARAMETER true

add_parameter F_CLK INTEGER
set_parameter_property F_CLK SYSTEM_INFO {CLOCK_RATE clock_reset}
set_parameter_property F_CLK DISPLAY_NAME F_CLK
set_parameter_property F_CLK DESCRIPTION "System clock frequency"
set_parameter_property F_CLK UNITS megahertz

add_parameter F_SPI INTEGER
set_parameter_property F_SPI SYSTEM_INFO {CLOCK_RATE clock_spi}
set_parameter_property F_SPI DISPLAY_NAME F_SPI
set_parameter_property F_SPI DESCRIPTION "SPI clock frequency"
set_parameter_property F_SPI UNITS megahertz

# add_display_item "Base time period options" BTP_N parameter
# add_display_item "Base time period options" BTP_O parameter
# add_display_item "Clock dividers"           F_CLK parameter
# add_display_item "Clock dividers"           CDR_N parameter
# add_display_item "Clock dividers"           CDR_O parameter

# connection point clock_reset
add_interface clock_reset clock end

set_interface_property clock_reset ENABLED true

add_interface_port clock_reset clk clk   Input 1
add_interface_port clock_reset rst reset Input 1

# connection point clock_spi
add_interface clock_spi clock end

set_interface_property clock_spi ENABLED true

add_interface_port clock_spi clk_spi clk Input 1

# connection point xip
add_interface xip avalon end
set_interface_property xip addressAlignment DYNAMIC
set_interface_property xip associatedClock clock_reset
set_interface_property xip burstOnBurstBoundariesOnly false
set_interface_property xip explicitAddressSpan 0
set_interface_property xip holdTime 0
set_interface_property xip isMemoryDevice true
set_interface_property xip isNonVolatileStorage true
set_interface_property xip linewrapBursts false
set_interface_property xip maximumPendingReadTransactions 0
set_interface_property xip printableDevice false
set_interface_property xip readLatency 0
set_interface_property xip readWaitStates 0
set_interface_property xip readWaitTime 0
set_interface_property xip setupTime 0
set_interface_property xip timingUnits Cycles

set_interface_property xip ASSOCIATED_CLOCK clock_reset
set_interface_property xip ENABLED true

add_interface_port xip xip_ren read        Input  1
add_interface_port xip xip_adr address     Input  XAW
add_interface_port xip xip_rdt readdata    Output 32
add_interface_port xip xip_wdt waitrequest Output 1

# connection point err
add_interface err interrupt end
set_interface_property err associatedClock clock_reset
set_interface_property err associatedAddressablePoint xip

set_interface_property err ASSOCIATED_CLOCK clock_reset
set_interface_property err ENABLED true

add_interface_port err xip_err irq Output 1

# connection point reg
add_interface reg avalon end
set_interface_property reg addressAlignment DYNAMIC
set_interface_property reg associatedClock clock_reset
set_interface_property reg burstOnBurstBoundariesOnly false
set_interface_property reg explicitAddressSpan 0
set_interface_property reg holdTime 0
set_interface_property reg isMemoryDevice false
set_interface_property reg isNonVolatileStorage false
set_interface_property reg linewrapBursts false
set_interface_property reg maximumPendingReadTransactions 0
set_interface_property reg printableDevice false
set_interface_property reg readLatency 0
set_interface_property reg readWaitStates 0
set_interface_property reg readWaitTime 0
set_interface_property reg setupTime 0
set_interface_property reg timingUnits Cycles
set_interface_property reg writeWaitTime 0

set_interface_property reg ASSOCIATED_CLOCK clock_reset
set_interface_property reg ENABLED true

add_interface_port reg reg_ren read      Input  1
add_interface_port reg reg_wen write     Input  1
add_interface_port reg reg_adr address   Input  2
add_interface_port reg reg_wdt writedata Input  32
add_interface_port reg reg_rdt readdata  Output 32

# connection point irq
add_interface irq interrupt end
set_interface_property irq associatedClock clock_reset
set_interface_property irq associatedAddressablePoint reg

set_interface_property irq ASSOCIATED_CLOCK clock_reset
set_interface_property irq ENABLED true

add_interface_port irq reg_irq irq Output 1

# connection point conduit
add_interface spi conduit end

set_interface_property irq ASSOCIATED_CLOCK clock_spi
set_interface_property spi ENABLED true

add_interface_port spi spi_sclk_i export Input  1
add_interface_port spi spi_sclk_o export Output 1
add_interface_port spi spi_sclk_e export Output 1
add_interface_port spi spi_sio_i  export Input  4
add_interface_port spi spi_sio_o  export Output 4
add_interface_port spi spi_sio_e  export Output 4
add_interface_port spi spi_ss_i   export Input  SSW
add_interface_port spi spi_ss_o   export Output SSW
add_interface_port spi spi_ss_e   export Output SSW

# proc validation_callback {} {
#   # check if overdrive is enabled
#   set ovd_e [get_parameter_value OVD_E]
#   # get clock frequency in Hz
#   set f     [get_parameter_value F_CLK]
#   # get base time periods
#   set btp_n [get_parameter_value BTP_N]
#   set btp_o [get_parameter_value BTP_O]
#   # enable/disable editing of overdrive divider
#   set_parameter_property BTP_O ENABLED [expr {$ovd_e ? "true" : "false"}]
#   # compute normal mode divider
#   if {$btp_n=="5.0"} {
#     set d_n [expr {$f/200000}]
#     set t_n [expr {1000000.0/($f/$d_n)}]
#     set e_n [expr {$t_n/5.0-1}]
#   } elseif {$btp_n=="7.5"} {
#     set d_n [expr {$f/133333}]
#     set t_n [expr {1000000.0/($f/$d_n)}]
#     set e_n [expr {$t_n/7.5-1}]
#   } elseif {$btp_n=="6.0"} {
#     set d_n [expr {$f/133333}]
#     set t_n [expr {$d_n*1000000.0/$f}]
#     if {$t_n>7.5} {
#       set e_n [expr {$t_n/7.5-1}]
#     } elseif {6.0>$t_n} {
#       set e_n [expr {$t_n/6.0-1}]
#     } else {
#       set e_n 0.0
#     }
#   }
#   # compute overdrive mode divider
#   if {$btp_o=="1.0"} {
#     set d_o [expr {$f/1000000}]
#     set t_o [expr {1000000.0/($f/$d_o)}]
#     set e_o [expr {$t_o/1.0-1}]
#   } elseif {$btp_o=="0.5"} {
#     set d_o [expr {$f/1500000}]
#     set t_o [expr {$d_o*1000000.0/$f}]
#     if {$t_o>(2.0/3)} {
#       set e_o [expr {$t_o/(2.0/3)-1}]
#     } elseif {0.5>$t_o} {
#       set e_o [expr {$t_o/0.5-1}]
#     } else {
#       set e_o 0.0
#     }
#   }
#   # set divider values
#                set_parameter_value CDR_N [expr {$d_n-1}]
#   if {$ovd_e} {set_parameter_value CDR_O [expr {$d_o-1}]}
#   # report BTP values and relative errors
#   send_message info "BTP_N (normal    mode 'base time period') is [format %.2f $t_n], relative error is [format %.1f [expr {$e_n*100}]]%."
#   send_message info "BTP_O (overdrive mode 'base time period') is [format %.2f $t_o], relative error is [format %.1f [expr {$e_o*100}]]%."
#   # repport validatio errors if relative error are outside accepted bounds (2%)
#   if {abs($e_n)>0.02} {send_message error "BTP_N is outside accepted bounds (relative error > 2%). Use a different 'base time period' or system frequency."}
#   if {abs($e_o)>0.02} {send_message error "BTP_O is outside accepted bounds (relative error > 2%). Use a different 'base time period' or system frequency."}
# }
# 
# proc elaboration_callback {} {
#   # add software defines
#   set_module_assignment embeddedsw.CMacro.OWN          [get_parameter_value OWN  ]
#   set_module_assignment embeddedsw.CMacro.CDR_E [expr {[get_parameter_value CDR_E]?1:0}]
#   set_module_assignment embeddedsw.CMacro.OVD_E [expr {[get_parameter_value OVD_E]?1:0}]
#   set_module_assignment embeddedsw.CMacro.BTP_N      \"[get_parameter_value BTP_N]\"
#   set_module_assignment embeddedsw.CMacro.BTP_O      \"[get_parameter_value BTP_O]\"
#   set_module_assignment embeddedsw.CMacro.CDR_N        [get_parameter_value CDR_N]
#   set_module_assignment embeddedsw.CMacro.CDR_O        [get_parameter_value CDR_O]
#   # get clock frequency in Hz
#   set f     [get_parameter_value F_CLK]
#   # get base time period
#   set btp_n [get_parameter_value BTP_N]
#   # get clock divider ratio
#   set cdr_n [get_parameter_value CDR_N]
#   # compute delay time in seconds [s]
#   if {$btp_n=="5.0"} {
#     set t_dly [expr {200.*($cdr_n+1)/$f}]
#   } elseif {$btp_n=="7.5"} {
#     set t_dly [expr {128.*($cdr_n+1)/$f}]
#   } elseif {$btp_n=="6.0"} {
#     set t_dly [expr {160.*($cdr_n+1)/$f}]
#   }
#   # give the software a u16.16 representation of delay frequency in kilo hertz [kHz]
#   set_module_assignment embeddedsw.CMacro.F_DLY [format %.0f [expr {pow(2,16) / (1000*$t_dly)}]]
# }
