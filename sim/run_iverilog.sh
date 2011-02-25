#!/bin/bash

# cleanup first
rm spi.out
rm spi.fst
rm spi.cdd
rm flash.hex

# convert Flash binary file into hexdecimal
xxd -ps -c 1 flash.bin >> flash.hex

# compile Verilog sources (RTL and slave models) and C++ testbench with Verilator
verilator -Wall --cc --trace --exe spi_tb.cpp hdl/spi_wrp.v hdl/sockit_spi.v hdl/sockit_spi_xip.v hdl/sockit_spi_fifo.v hdl/spi_flash_model.v
verilator -Wall --cc --trace --exe --prefix Vspi --top-module spi_wrp \
../hdl/spi_wrp.v \
../hdl/sockit_spi.v \
../hdl/sockit_spi_xip.v \
../hdl/sockit_spi_fifo.v \
../hdl/spi_flash_model.v \
../src/spi_tb.cpp
# build C++ project
make -j -C obj_dir/ -f Vspi.mk Vspi
# run executable simulation
obj_dir/Vspi


# compile Verilog sources (testbench and RTL) with Icarus Verilog
iverilog -o spi.out \
../hdl/spi_tb.v \
../hdl/sockit_spi.v \
../hdl/sockit_spi_xip.v \
../hdl/sockit_spi_fifo.v \
../hdl/spi_slave_model.v \
../hdl/spi_flash_model.v
#-I ../dev/NU_N25Q128A230B_VG14/ \
#../dev/NU_N25Q128A230B_VG14/code/N25Q128A230B.v
#../hdl/MX25L12845E.v \
#../hdl/s25fl129p00.v

# compile verilog sources (testbench and RTL) for coverage
#covered score -o spi.cdd -g 2 -t spi_tb \
covered score -o spi.cdd -g 2 -t sockit_spi -i spi_tb.sockit_spi \
-v ../hdl/spi_tb.v \
-v ../hdl/sockit_spi.v \
-v ../hdl/sockit_spi_xip.v \
-v ../hdl/spi_slave_model.v \
-v ../hdl/spi_flash_model.v

# run the simulation
vvp spi.out -fst

# add simulation data to coverage database
covered score -cdd spi.cdd -fst spi.fst -t sockit_spi -i spi_tb.sockit_spi

# open the waveform and detach it
#gtkwave spi.fst gtkwave.sav &
