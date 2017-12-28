#!/bin/bash

# cleanup first
rm -rf obj_dir
rm -f  spi.vcd
rm -f  spi.cdd
rm -f  flash.hex

# convert Flash binary file into hexdecimal
xxd -ps -c 1 flash.bin >> flash.hex

# compile Verilog sources (RTL and slave models) and C++ testbench with Verilator
verilator -Wall --cc --trace --exe --prefix Vspi --top-module spi_wrp \
../hdl/spi_wrp.sv \
../hdl/sockit_spi.sv \
../hdl/sockit_spi_reg.sv \
../hdl/sockit_spi_xip.sv \
../hdl/sockit_spi_dma.sv \
../hdl/sockit_spi_rpo.sv \
../hdl/sockit_spi_rpi.sv \
../hdl/sockit_spi_cdc.sv \
../hdl/sockit_spi_ser.sv \
../hdl/spi_flash_model.sv \
../src/spi_tb.cpp
# build C++ project
make -j -C obj_dir/ -f Vspi.mk Vspi
# run executable simulation
obj_dir/Vspi

# open the waveform and detach it
gtkwave spi.vcd sim_verilator.sav &
