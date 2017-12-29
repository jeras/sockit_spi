#source "axi4_if.tcl"
#source "axi4_lite_if.tcl"
#source "axi4_stream_if.tcl"
#source "sys_bus_if.tcl"

# set top hierarcy name
set top spi_tb

onerror {resume}
# signals
add wave -noupdate /${top}/clk
add wave -noupdate /${top}/rst
