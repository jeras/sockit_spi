////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) slave model                                      //
//                                                                            //
//  Copyright (C) 2010  Iztok Jeras                                           //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  This HDL is free hardware: you can redistribute it and/or modify          //
//  it under the terms of the GNU Lesser General Public License               //
//  as published by the Free Software Foundation, either                      //
//  version 3 of the License, or (at your option) any later version.          //
//                                                                            //
//  This RTL is distributed in the hope that it will be useful,               //
//  but WITHOUT ANY WARRANTY; without even the implied warranty of            //
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             //
//  GNU General Public License for more details.                              //
//                                                                            //
//  You should have received a copy of the GNU General Public License         //
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.     //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

`timescale 1us / 1ns

module spi_slave_model #(
  parameter DLY  = 8,     // data delay
  parameter CPOL = 1'b0,  // polarity
  parameter CPHA = 1'b0,  // phase
  parameter MODE = 2'd1   // mode (0-3wire, 1-SPI, 2-duo, 3-quad)
)(
  input wire ss_n,   // slave select  (active low)
  input wire sclk,   // serial clock
  inout wire mosi,   // master output slave  input / SIO[0]
  inout wire miso,   // maste   input slave output / SIO[1]
  inout wire wp_n,   // write protect (active low) / SIO[2]
  inout wire hold_n  // clock hold    (active low) / SIO[3]
);

// IO data width
localparam IOW = MODE[1] ? (MODE[0] ? 4 : 2) : 1;

wire              clk;    // local clock
wire              rst;    // local reset

reg               oen;    // output enable

wire    [IOW-1:0] sig_i;  // input signal vector
reg     [IOW-1:0] reg_i;  // input register
reg [DLY*IOW-1:0] reg_d;  // data shift register
reg     [IOW-1:0] reg_o;  // output register
wire    [IOW-1:0] sig_o;  // output signal vector

integer           cnt_c;  // clock period counter

// local clock and reset
assign clk = sclk;
assign rst = ss_n;

// input signal vector
generate case (MODE)
  0 :  assign sig_i = {                    mosi};
  1 :  assign sig_i = {                    mosi};
  2 :  assign sig_i = {              miso, mosi};
  3 :  assign sig_i = {hold_n, wp_n, miso, mosi};
endcase endgenerate

// clock period counter
always @ (posedge clk, posedge rst)          
if (rst)  cnt_c  <= 0;                
else      cnt_c  <= cnt_c + 1;

// output enable handler
initial oen = 1'b1;

// input register
always @ (posedge  sclk, posedge rst)
if (rst)  reg_i  <= {IOW{1'bx}};
else      reg_i  <= sig_i;

// data shift register
always @ (posedge ~sclk, posedge rst)
if (rst)  reg_d <= {DLY{1'bx}};
else      reg_d <= {reg_d[DLY-1-IOW:0], CPHA ? sig_i : reg_i};

// output register
always @ (posedge  sclk, posedge rst)
if (rst)  reg_o  <= {IOW{1'bx}};
else      reg_o  <= reg_d[DLY-1-IOW+:IOW];

// output signal vector
assign sig_o = CPHA ? reg_o : reg_d[DLY-1-IOW+:IOW];

// output drivers
generate case (MODE)
//  0 :  assign {hold_n, wp_n, miso, mosi} = oen ? {    1'bz,     1'bz,     1'bz, sig_o[0]} : 4'bzzzz;
  1 :  assign {hold_n, wp_n, miso, mosi} = oen ? {    1'bz,     1'bz, sig_o[0],     1'bz} : 4'bzzzz;
//  2 :  assign {hold_n, wp_n, miso, mosi} = oen ? {    1'bz,     1'bz, sig_o[1], sig_o[0]} : 4'bzzzz;
//  3 :  assign {hold_n, wp_n, miso, mosi} = oen ? {sig_o[3], sig_o[2], sig_o[1], sig_o[0]} : 4'bzzzz;
endcase endgenerate

initial $display ("MODE = %d, IOW = %d", MODE, IOW);

endmodule
