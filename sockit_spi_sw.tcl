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

# Create a new driver
create_driver sockit_spi_driver

# Association with hardware
set_sw_property hw_class_name sockit_spi

# Driver version
set_sw_property version 0.5

# Hardware compatibility
set_sw_property min_compatible_hw_version 0.5

# Interrupt properties
set_sw_property isr_preemption_supported true
set_sw_property supported_interrupt_apis "legacy_interrupt_api enhanced_interrupt_api"

# Initialize the driver in alt_sys_init()
set_sw_property auto_initialize true

# Location in generated BSP that above sources will be copied into
set_sw_property bsp_subdirectory drivers

# C source files
add_sw_property       c_source HAL/src/sockit_spi.c

# Include files
add_sw_property include_source inc/sockit_spi_regs.h
add_sw_property include_source HAL/inc/sockit_spi.h

# This driver supports HAL & UCOSII BSP (OS) types
add_sw_property supported_bsp_type HAL
add_sw_property supported_bsp_type UCOSII

# Driver configuration options
#add_sw_setting boolean_define_only public_mk_define polling_driver_enable  SOCKIT_OWM_POLLING    false "Small-footprint (polled mode) driver"
#add_sw_setting boolean_define_only public_mk_define hardware_delay_enable  SOCKIT_OWM_HW_DLY     true  "Mili second delay implemented in hardware"
#add_sw_setting boolean_define_only public_mk_define error_detection_enable SOCKIT_OWM_ERR_ENABLE true  "Implement error detection support"
#add_sw_setting boolean_define_only public_mk_define error_detection_small  SOCKIT_OWM_ERR_SMALL  true  "Reduced memory consumption for error detection"

# Enable application layer code
#add_sw_setting boolean_define_only public_mk_define enable_A SOCKIT_OWM_A false "Enable driver A"
