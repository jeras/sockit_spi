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
../hdl/spi_wrp.v \
../hdl/sockit_spi.v \
../hdl/sockit_spi_reg.v \
../hdl/sockit_spi_xip.v \
../hdl/sockit_spi_dma.v \
../hdl/sockit_spi_rpo.v \
../hdl/sockit_spi_rpi.v \
../hdl/sockit_spi_cdc.v \
../hdl/sockit_spi_ser.v \
../hdl/spi_flash_model.v \
../src/spi_tb.cpp
# build C++ project
make -j -C obj_dir/ -f Vspi.mk Vspi
# run executable simulation
obj_dir/Vspi

# open the waveform and detach it
gtkwave spi.vcd sim_verilator.sav &
