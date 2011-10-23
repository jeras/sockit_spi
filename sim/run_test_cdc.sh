#!/bin/bash

# cleanup first
rm -f cdc_tb.out

# compile Verilog sources (testbench and RTL) with Icarus Verilog
iverilog -o cdc_tb.out ../hdl/cdc_tb.v ../hdl/sockit_spi_cdc.v

# run the simulation
vvp cdc_tb.out -fst

# open the waveform and detach it
gtkwave cdc.fst sim_test_cdc.sav &
