REM cmd script for running the spi example

:: cleanup first
erase spi.out
erase spi.vcd

:: compile the verilog sources (testbench and RTL)
iverilog -g specify -o spi.out  spi_tb.sv spi.sv spi_slave_model.sv s25fl129p00.v 
:: run the simulation
vvp spi.out

:: open the waveform and detach it
gtkwave spi.vcd gtkwave.sav &
