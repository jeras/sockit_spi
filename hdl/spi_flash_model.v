////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) flash model                                      //
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

module spi_flash_model #(
  // hardware layer protocol parameters
  parameter DIOM = 2'd1,        // data IO mode (0-3wire, 1-SPI, 2-duo, 3-quad)
  parameter MODE = 2'd0,        // clock mode {CPOL, CPHA}
  parameter CPOL = MODE[1],     // clock polarity
  parameter CPHA = MODE[0],     // clock phase
  // internal logic parameters
  parameter MSZ  = 1024,        // data memory size
  parameter FILE = "flash.bin"  // flash contents (binary) file name
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

// input stage
reg     [3:0] i_sig;  // input signal vector
reg     [3:0] i_reg;  // input phase register
reg     [7:0] i_tmp;  // input data byte temporary register
reg     [7:0] i_dat;  // input data byte

// internal machinery
reg     [2:0] m_bit;  // bit (clock) counter
reg           m_byt;  // byte end
integer       m_cnt;  // byte counter
reg           m_oen;  // output enable
reg     [1:0] m_iow;  // data IO mode
reg     [7:0] m_cmd;  // command
reg    [23:0] m_adr;  // address
reg     [7:0] m_wdt;  // write data
reg     [7:0] m_rdt;  // read  data

// internal memory
reg     [7:0] mem [0:MSZ-1];

// output, output enable
reg     [3:0] o_tmp;  // output data mixer
reg     [3:0] o_reg;  // output register
wire    [3:0] o_sig;  // output signal vector
reg           e_reg;  // output enable register
wire          e_sig;  // output enable signal vector
reg     [3:0] sio;    // serial input output

////////////////////////////////////////////////////////////////////////////////
// memory initialization                                                      //
////////////////////////////////////////////////////////////////////////////////

integer f;  // file pointer
integer s;  // file status

initial begin
  f = $fopen(FILE, "r");
  s = $fread(mem, f);
end

////////////////////////////////////////////////////////////////////////////////
// clock and reset                                                            //
////////////////////////////////////////////////////////////////////////////////

assign clk = sclk ^ ~CPOL;
assign rst = ss_n;

////////////////////////////////////////////////////////////////////////////////
// data input                                                                 //
////////////////////////////////////////////////////////////////////////////////

// input signal vector
always @ (*)
case (m_iow)
  2'd0 :  i_sig = {  1'bx, 1'bx, 1'bx, mosi};  // 3-wire
  2'd1 :  i_sig = {  1'bx, 1'bx, 1'bx, mosi};  // spi
  2'd2 :  i_sig = {  1'bx, 1'bx, miso, mosi};  // dual
  2'd3 :  i_sig = {hold_n, wp_n, miso, mosi};  // quad
endcase

// input phase register
always @ (negedge clk, posedge rst)
if (rst)  i_reg <= 4'bxxxx;
else      i_reg <= i_sig;

// input mixer
always @ (*)
case (m_iow)
  2'd0 :  i_dat = {i_tmp[7-1:0], CPHA ? i_sig [0:0] : i_reg [0:0]};  // 3-wire
  2'd1 :  i_dat = {i_tmp[7-1:0], CPHA ? i_sig [0:0] : i_reg [0:0]};  // spi
  2'd2 :  i_dat = {i_tmp[7-2:0], CPHA ? i_sig [1:0] : i_reg [1:0]};  // dual
  2'd3 :  i_dat = {i_tmp[7-4:0], CPHA ? i_sig [3:0] : i_reg [3:0]};  // quad
endcase

// temporary input data register
always @ (posedge clk, posedge rst)
if (rst)  i_tmp <= 8'hxx;
else      i_tmp <= i_dat;

////////////////////////////////////////////////////////////////////////////////
// internals                                                                  //
////////////////////////////////////////////////////////////////////////////////

// clock period counter
always @ (posedge clk, posedge rst)
if (rst)  m_bit <= 3'b000;
else      m_bit <= m_bit + 3'b001;

// byte end
always @ (*)
case (m_iow)
  2'd0 :  m_byt <= &m_bit[2:0];  // 3-wire
  2'd1 :  m_byt <= &m_bit[2:0];  // spi
  2'd2 :  m_byt <= &m_bit[1:0];  // dual
  2'd3 :  m_byt <= &m_bit[0:0];  // quad
endcase

// clock period counter
always @ (posedge clk, posedge rst)
if (rst)         m_cnt <= 0;
else if (m_byt)  m_cnt <= m_cnt + 1;

// command register
always @ (posedge clk, posedge rst)
if (rst)           m_cmd <= 8'h00;
else if (m_byt) begin
  if (m_cnt == 0)  m_cmd <= i_dat;
end

// address register
always @ (posedge clk, posedge rst)
if (rst)           m_adr        <= 24'hxxxxxx;
else if (m_byt) begin
  if (m_cnt == 1)  m_adr[ 7: 0] <= i_dat;
  if (m_cnt == 2)  m_adr[15: 8] <= i_dat;
  if (m_cnt == 3)  m_adr[23:16] <= i_dat;
end

//                 output enable          IO mode                              read data
always @ (*)
case (m_cmd)
  8'h03   : begin  m_oen = (m_cnt >= 4);  m_iow =                2'd1       ;  m_rdt = mem [m_adr + m_byt - 4];  end  // Read Data
  8'h0b   : begin  m_oen = (m_cnt >= 5);  m_iow =                2'd1       ;  m_rdt = mem [m_adr + m_cnt - 5];  end  // Fast Read
  8'h3b   : begin  m_oen = (m_cnt >= 5);  m_iow = (m_cnt >= 5) ? 2'd1 : 2'd2;  m_rdt = mem [m_adr + m_byt - 5];  end  // Fast Read Dual Output
  8'h6b   : begin  m_oen = (m_cnt >= 5);  m_iow = (m_cnt >= 5) ? 2'd1 : 2'd3;  m_rdt = mem [m_adr + m_byt - 5];  end  // Fast Read Quad Output
  8'hbb   : begin  m_oen = (m_cnt >= 5);  m_iow = (m_cnt >= 5) ? 2'd1 : 2'd2;  m_rdt = mem [m_adr + m_byt - 5];  end  // Fast Read Dual IO
  8'heb   : begin  m_oen = (m_cnt >= 7);  m_iow = (m_cnt >= 7) ? 2'd1 : 2'd3;  m_rdt = mem [m_adr + m_byt - 7];  end  // Fast Read Quad IO
  8'he7   : begin  m_oen = (m_cnt >= 6);  m_iow = (m_cnt >= 6) ? 2'd1 : 2'd3;  m_rdt = mem [m_adr + m_byt - 6];  end  // Word Read Quad IO 
  8'he3   : begin  m_oen = (m_cnt >= 5);  m_iow = (m_cnt >= 5) ? 2'd1 : 2'd3;  m_rdt = mem [m_adr + m_byt - 5];  end  // octal Word Read Quad IO 
  default : begin  m_oen = 1'b0        ;  m_iow =                2'd1       ;  m_rdt = 8'hxx                  ;  end  //
endcase

////////////////////////////////////////////////////////////////////////////////
// data output                                                                //
////////////////////////////////////////////////////////////////////////////////

// output mixer
always @ (*)
case (m_iow)
  2'd0 :  o_tmp = {1'bx, 1'bx, 1'bx, m_rdt[7-m_bit*1   ]      };  // 3-wire
  2'd1 :  o_tmp = {1'bx, 1'bx,       m_rdt[7-m_bit*1   ], 1'bx};  // spi
  2'd2 :  o_tmp = {1'bx, 1'bx,       m_rdt[7-m_bit*2+:2]      };  // dual
  2'd3 :  o_tmp = {                  m_rdt[7-m_bit*4+:4]      };  // quad
endcase

// phase output register
always @ (negedge clk, posedge rst)
if (rst)  o_reg  <= 4'bxxxx;
else      o_reg  <= o_tmp;

// phase output enable register
always @ (negedge clk, posedge rst)
if (rst)  e_reg <= 1'b0;
else      e_reg <= m_oen;

// output signal vector
assign o_sig = CPHA ? o_reg : o_tmp;

// output enable
assign e_sig = CPHA ? e_reg : m_oen;

// output drivers
always @ (*)
case (m_iow)
  2'd0 :  sio = e_sig ? {    1'bz,     1'bz,     1'bz, o_sig[0]} : 4'bzzzz;  // 3-wire
  2'd1 :  sio = e_sig ? {    1'bz,     1'bz, o_sig[1],     1'bz} : 4'bzzzz;  // spi
  2'd2 :  sio = e_sig ? {    1'bz,     1'bz, o_sig[1], o_sig[0]} : 4'bzzzz;  // dual
  2'd3 :  sio = e_sig ? {o_sig[3], o_sig[2], o_sig[1], o_sig[0]} : 4'bzzzz;  // quad
endcase

// output data
assign {hold_n, wp_n, miso, mosi} = sio;

endmodule
