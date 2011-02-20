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

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// system signals
wire          clk;    // local clock
wire          rst;    // local reset

integer       cnt_c;  // clock period counter

// mode signals
reg     [1:0] mode;   // mode data

wire          oen_s;
reg           oen_r;
wire          oen;    // output enable

// spi signals
reg     [3:0] sig_i;  // input signal vector
reg     [3:0] reg_i;  // input register
reg [DLY-1:0] reg_d;  // data shift register
reg     [3:0] reg_o;  // output register
wire    [3:0] sig_o;  // output signal vector
reg     [3:0] sio;    // serial input output

////////////////////////////////////////////////////////////////////////////////
// mode control                                                               //
////////////////////////////////////////////////////////////////////////////////

// local clock and reset
assign clk = sclk ^ CPOL;
assign rst = ss_n;

// clock period counter
always @ (negedge clk, posedge rst)
if (rst)  cnt_c  <= 0;
else      cnt_c  <= cnt_c + 1;

// output enable signal
assign oen_s = ~ss_n & (cnt_c >= DLY);

// output enable register
always @ (posedge clk, posedge rst)
if (rst)  oen_r <= 1'b0;
else      oen_r <= oen_s;

//always @ (*)  mode = MODE_DAT[1] ? ((cnt_c > DLY) ? MODE_DAT : 2'd1) : MODE_DAT;
initial mode = MODE_DAT;

////////////////////////////////////////////////////////////////////////////////
// spi data flow                                                              //
////////////////////////////////////////////////////////////////////////////////

// input signal vector
always @ (*) case (mode)
  2'd0 :  sig_i = {  1'bx, 1'bx, 1'bx, mosi};
  2'd1 :  sig_i = {  1'bx, 1'bx, 1'bx, mosi};
  2'd2 :  sig_i = {  1'bx, 1'bx, miso, mosi};
  2'd3 :  sig_i = {hold_n, wp_n, miso, mosi};
endcase

// input register
always @ (posedge clk, posedge rst)
if (rst)  reg_i  <= 4'bxxxx;
else      reg_i  <= sig_i;

// data shift register
always @ (negedge clk, posedge rst)
if (rst)  reg_d <= {DLY{1'bx}};
else case (mode)
  2'd0 :  reg_d <= {reg_d[DLY-1-1:0], CPHA ? sig_i [0:0] : reg_i [0:0]};
  2'd1 :  reg_d <= {reg_d[DLY-1-1:0], CPHA ? sig_i [0:0] : reg_i [0:0]};
  2'd2 :  reg_d <= {reg_d[DLY-2-1:0], CPHA ? sig_i [1:0] : reg_i [1:0]};
  2'd3 :  reg_d <= {reg_d[DLY-4-1:0], CPHA ? sig_i [3:0] : reg_i [3:0]};
endcase

// output register
always @ (posedge clk, posedge rst)
if (rst)  reg_o  <= 4'bxxxx;
else      reg_o  <= reg_d[DLY-4+:4];

// output signal vector
assign sig_o = CPHA ? reg_o : reg_d[DLY-4+:4];

// output enable
assign oen   = CPHA ? oen_r : oen_s;

// output drivers
always @ (*) case (mode)
  2'd0 :  sio = oen ? {    1'bz,     1'bz,     1'bz, sig_o[3]} : 4'bzzzz;
  2'd1 :  sio = oen ? {    1'bz,     1'bz, sig_o[3],     1'bz} : 4'bzzzz;
  2'd2 :  sio = oen ? {    1'bz,     1'bz, sig_o[3], sig_o[2]} : 4'bzzzz;
  2'd3 :  sio = oen ? {sig_o[3], sig_o[2], sig_o[1], sig_o[0]} : 4'bzzzz;
endcase

// output data
assign {hold_n, wp_n, miso, mosi} = sio;

endmodule
