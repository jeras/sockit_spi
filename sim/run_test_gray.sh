#!/bin/bash

# cleanup first
rm -f test_gray.out

# compile Verilog sources (testbench and RTL) with Icarus Verilog
iverilog -o test_gray.out ../hdl/test_gray.v

# run the simulation
vvp test_gray.out
