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
  parameter DLY  = 8,            // data delay
  parameter MODE_DAT = 2'd1,     // mode data (0-3wire, 1-SPI, 2-duo, 3-quad)
  parameter MODE_CLK = 2'd0,     // mode clock {CPOL, CPHA}
  parameter CPOL = MODE_CLK[1],  // clock polarity
  parameter CPHA = MODE_CLK[0]   // clock phase
)(
  input wire ss_n,   // slave select  (active low)
  input wire sclk,   // serial clock
  inout wire mosi,   // master output slave  input / SIO[0]
  inout wire miso,   // maste   input slave output / SIO[1]
  inout wire wp_n,   // write protect (active low) / SIO[2]
  inout wire hold_n  // clock hold    (active low) / SIO[3]
);

// IO data width
localparam IOW = MODE_DAT[1] ? (MODE_DAT[0] ? 4 : 2) : 1;

wire              clk;    // local clock
wire              rst;    // local reset

wire              oen;    // output enable

wire    [IOW-1:0] sig_i;  // input signal vector
reg     [IOW-1:0] reg_i;  // input register
reg [DLY*IOW-1:0] reg_d;  // data shift register
reg     [IOW-1:0] reg_o;  // output register
wire    [IOW-1:0] sig_o;  // output signal vector

integer           cnt_c;  // clock period counter

// local clock and reset
assign clk = sclk ^ CPOL;
assign rst = ss_n;

// input signal vector
generate case (MODE_DAT)
  2'd0 :  assign sig_i = {                    mosi};
  2'd1 :  assign sig_i = {                    mosi};
  2'd2 :  assign sig_i = {              miso, mosi};
  2'd3 :  assign sig_i = {hold_n, wp_n, miso, mosi};
endcase endgenerate

// clock period counter
always @ (posedge clk, posedge rst)          
if (rst)  cnt_c  <= 0;                
else      cnt_c  <= cnt_c + 1;

// output enable handler
assign oen = ~ss_n & (cnt_c > DLY);

// input register
always @ (negedge clk, posedge rst)
if (rst)  reg_i  <= {IOW{1'bx}};
else      reg_i  <= sig_i;

// data shift register
always @ (posedge clk, posedge rst)
if (rst)  reg_d <= {DLY{1'bx}};
else      reg_d <= {reg_d[DLY-1-IOW:0], CPHA ? sig_i : reg_i};

// output register
always @ (negedge clk, posedge rst)
if (rst)  reg_o  <= {IOW{1'bx}};
else      reg_o  <= reg_d[DLY-1-IOW+:IOW];

// output signal vector
assign sig_o = CPHA ? reg_o : reg_d[DLY-1-IOW+:IOW];

// output drivers
generate case (MODE_DAT)
  2'd0 :  assign {hold_n, wp_n, miso, mosi} = oen ? {    1'bz,     1'bz,     1'bz, sig_o[0]} : 4'bzzzz;
  2'd1 :  assign {hold_n, wp_n, miso, mosi} = oen ? {    1'bz,     1'bz, sig_o[0],     1'bz} : 4'bzzzz;
  2'd2 :  assign {hold_n, wp_n, miso, mosi} = oen ? {    1'bz,     1'bz, sig_o[1], sig_o[0]} : 4'bzzzz;
  2'd3 :  assign {hold_n, wp_n, miso, mosi} = oen ? {sig_o[3], sig_o[2], sig_o[1], sig_o[0]} : 4'bzzzz;
endcase endgenerate

endmodule
