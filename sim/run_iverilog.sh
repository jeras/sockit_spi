#!/bin/bash

# cleanup first
rm -f spi.out
rm -f spi.fst
rm -f spi.cdd
rm -f flash.hex

# convert Flash binary file into hexdecimal
xxd -ps -c 1 flash.bin >> flash.hex

# convert DMA memory binary file into hexadecimal
xxd -ps -c 4 lorem-ipsum.txt >> dma_mem.hex

# compile Verilog sources (testbench and RTL) with Icarus Verilog
iverilog -g2012 -o spi.out \
../hdl/spi_tb.sv \
../hdl/sockit_spi.sv \
../hdl/sockit_spi_reg.sv \
../hdl/sockit_spi_xip.sv \
../hdl/sockit_spi_dma.sv \
../hdl/sockit_spi_rpo.sv \
../hdl/sockit_spi_rpi.sv \
../hdl/sockit_spi_cdc.sv \
../hdl/sockit_spi_ser.sv \
../hdl/spi_slave_model.sv \
../hdl/spi_flash_model.sv
#-I ../dev/NU_N25Q128A230B_VG14/ \
#../dev/NU_N25Q128A230B_VG14/code/N25Q128A230B.v
#../hdl/MX25L12845E.v \
#../hdl/s25fl129p00.v

# # compile verilog sources (testbench and RTL) for coverage
# #covered score -o spi.cdd -g 2 -t spi_tb \
# covered score -o spi.cdd -g 2 -t sockit_spi -i spi_tb.sockit_spi \
# -v ../hdl/spi_tb.sv \
# -v ../hdl/sockit_spi.sv \
# -v ../hdl/sockit_spi_cdc.sv \
# -v ../hdl/sockit_spi_xip.sv \
# -v ../hdl/sockit_spi_dma.sv \
# -v ../hdl/spi_slave_model.sv \
# -v ../hdl/spi_flash_model.sv

# run the simulation
vvp spi.out -fst

# # add simulation data to coverage database
# covered score -cdd spi.cdd -fst spi.fst -t sockit_spi -i spi_tb.sockit_spi

# open the waveform and detach it
#gtkwave spi.fst sim_iverilog.sav &
