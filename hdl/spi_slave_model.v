////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) slave model                                      //
//                                                                            //
//  Copyright (C) 2011  Iztok Jeras                                           //
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
  parameter BFL = 1024   // buffer length
)(
  // configuration
  input wire [1:0] mod_clk,  // mode clock {CPOL, CPHA}
  input wire [1:0] mod_dat,  // mode data (0-3wire, 1-SPI, 2-duo, 3-quad)
  input wire       mod_oen,  // data output enable for half duplex modes
  input wire       mod_dir,  // shift direction (0 - LSB first, 1 - MSB first)
  // SPI signals
  input wire       ss_n,     // slave select  (active low)
  input wire       sclk,     // serial clock
  inout wire       mosi,     // master output slave  input / SIO[0]
  inout wire       miso,     // maste   input slave output / SIO[1]
  inout wire       wp_n,     // write protect (active low) / SIO[2]
  inout wire       hold_n    // clock hold    (active low) / SIO[3]
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// system signals
wire          clk_i;  // local clock input
wire          clk_o;  // local clock output
wire          rst;    // local reset

// IO signal vectors
wire    [3:0] sig_i;  // inputs
reg     [3:0] sig_o;  // outputs
reg     [3:0] sig_e;  // enables

// clock period counters
integer       cnt_i;  // bit counter input
integer       cnt_o;  // bit counter output

// buffers
reg [0:BFL-1] buf_i;  // data buffer input
reg [0:BFL-1] buf_o;  // data buffer output

////////////////////////////////////////////////////////////////////////////////
// clock and reset                                                            //
////////////////////////////////////////////////////////////////////////////////

// local clock and reset
assign clk_i =  sclk ^ mod_clk[1] ^ mod_clk[0];
assign clk_o = ~sclk ^ mod_clk[1] ^ mod_clk[0];
assign rst   =  ss_n;

////////////////////////////////////////////////////////////////////////////////
// input write into buffer                                                    //
////////////////////////////////////////////////////////////////////////////////

// input clock period counter
always @ (posedge clk_i, posedge ss_n)
if (ss_n)  cnt_i <= 0;
else       cnt_i <= cnt_i + 1;

// input signal vector
assign sig_i = {hold_n, wp_n, miso, mosi};

// input buffer
always @ (posedge clk_i)
if (~ss_n) case (mod_dat)
  2'd0 :  if (~mod_oen)  buf_i [  cnt_i   ] <= sig_i[  0];
  2'd1 :                 buf_i [  cnt_i   ] <= sig_i[  0];
  2'd2 :  if (~mod_oen)  buf_i [2*cnt_i+:2] <= sig_i[1:0];
  2'd3 :  if (~mod_oen)  buf_i [4*cnt_i+:4] <= sig_i[3:0];
endcase

////////////////////////////////////////////////////////////////////////////////
// output read from buffer                                                    //
////////////////////////////////////////////////////////////////////////////////

// clock period counter
always @ (posedge clk_o, posedge ss_n)
if (ss_n)  cnt_o <= 0;
else       cnt_o <= cnt_o + |cnt_i;

// output signal vector
always @ (*)
if (rst)  sig_o = 4'bxxxx;
else case (mod_dat)
  2'd0 :  sig_o = {2'bxx, 1'bx, buf_o [  cnt_o   ]      };
  2'd1 :  sig_o = {2'bxx,       buf_o [  cnt_o   ], 1'bx};
  2'd2 :  sig_o = {2'bxx,       buf_o [2*cnt_o+:2]      };
  2'd3 :  sig_o = {             buf_o [4*cnt_i+:4]      };
endcase

// output enable signal vector
always @ (*)
if (rst)  sig_e = 4'b0000;
else case (mod_dat)
  2'd0 :  sig_e = {2'b0, 1'b0, mod_oen      };
  2'd1 :  sig_e = {2'b0,       mod_oen, 1'b0};
  2'd2 :  sig_e = {2'b0,    {2{mod_oen}}    };
  2'd3 :  sig_e = {         {4{mod_oen}}    };
endcase

// output drivers
assign mosi   = sig_e [0] ? sig_o [0] : 1'bz;
assign miso   = sig_e [1] ? sig_o [1] : 1'bz;
assign wp_n   = sig_e [2] ? sig_o [2] : 1'bz;
assign hold_n = sig_e [3] ? sig_o [3] : 1'bz;

endmodule
