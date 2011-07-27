////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) flash model                                      //
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

module spi_flash_model #(
  // hardware layer protocol parameters
  parameter DIOM = 2'd1,         // data IO mode (0-3wire, 1-SPI, 2-duo, 3-quad)
  parameter MODE = 2'd0,         // clock mode {CPOL, CPHA}
  parameter CPOL = MODE[1],      // clock polarity
  parameter CPHA = MODE[0],      // clock phase
  // internal logic parameters
  parameter FBIN = "flash.bin",  // flash contents (binary) file name
  parameter FHEX = "flash.hex",  // flash contents (hex)    file name
  parameter MSZ  = 1024          // data memory size in bytes
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
wire          i_clk;  // local clock (input  registers)
wire          o_clk;  // local clock (output registers)
wire          rst;    // local reset

// input stage
reg     [7:0] i_dat;  // input data byte

// internal machinery
reg     [2:0] m_bit;  // bit (clock) counter
reg           m_byt;  // byte end
integer       m_cnt;  // byte counter
reg           m_oen;  // output (read) enable
reg           m_ien;  // input (write) enable
reg     [1:0] m_iow;  // data IO mode
reg     [7:0] m_cmd;  // command
reg    [31:0] m_adr;  // address

// internal memory
reg     [7:0] mem [0:MSZ-1];
/* verilator lint_off UNUSED */
reg    [31:0] m_oad;  // output (read) address
reg    [31:0] m_iad;  // input (write) address
/* verilator lint_on  UNUSED */
wire    [7:0] m_rdt;  // read  data

// output, output enable
wire    [7:0] o_dat;  // output data byte
reg     [3:0] o_tmp;  // output data mixer
reg     [3:0] o_ena;  // output enable

////////////////////////////////////////////////////////////////////////////////
// clock and reset                                                            //
////////////////////////////////////////////////////////////////////////////////

assign i_clk =  sclk ^ CPOL ^ CPHA;
assign o_clk = ~sclk ^ CPOL ^ CPHA;
assign rst   =  ss_n;

////////////////////////////////////////////////////////////////////////////////
// data input                                                                 //
////////////////////////////////////////////////////////////////////////////////

// input data register
always @ (posedge i_clk, posedge rst)
if (rst)  i_dat <= 8'hxx;
else case (m_iow)
  2'd0 :  i_dat <= {i_dat[7-1:0],                     mosi};  // 3-wire
  2'd1 :  i_dat <= {i_dat[7-1:0],                     mosi};  // spi
  2'd2 :  i_dat <= {i_dat[7-2:0],               miso, mosi};  // dual
  2'd3 :  i_dat <= {i_dat[7-4:0], hold_n, wp_n, miso, mosi};  // quad
endcase

////////////////////////////////////////////////////////////////////////////////
// internals                                                                  //
////////////////////////////////////////////////////////////////////////////////

// clock period counter
always @ (posedge o_clk, posedge rst)
if (rst)  m_bit <= 3'b000;
else case (m_iow)
  2'd0 :  m_bit <= m_bit + 3'd1;
  2'd1 :  m_bit <= m_bit + 3'd1;
  2'd2 :  m_bit <= m_bit + 3'd2;
  2'd3 :  m_bit <= m_bit + 3'd4;
endcase

// byte end
always @ (*)
case (m_iow)
  2'd0 :  m_byt = &m_bit[2:0];  // 3-wire
  2'd1 :  m_byt = &m_bit[2:0];  // spi
  2'd2 :  m_byt = &m_bit[2:1];  // dual
  2'd3 :  m_byt = &m_bit[2:2];  // quad
endcase

// clock period counter
always @ (posedge o_clk, posedge rst)
if (rst)         m_cnt <= 0;
else if (m_byt)  m_cnt <= m_cnt + 1;

// command register
always @ (posedge o_clk, posedge rst)
if (rst)           m_cmd <= 8'h00;
else if (m_byt) begin
  if (m_cnt == 0)  m_cmd <= i_dat;
end

// address register
always @ (posedge o_clk, posedge rst)
if (rst)           m_adr        <= 32'h00xxxxxx;
else if (m_byt) begin
  if (m_cnt == 1)  m_adr[23:16] <= i_dat;
  if (m_cnt == 2)  m_adr[15: 8] <= i_dat;
  if (m_cnt == 3)  m_adr[ 7: 0] <= i_dat;
end

always @ (*)
case (m_cmd)
  // read memory instuctions
  8'h03   : begin  m_ien = 1'b0;  m_oen = (m_cnt >= 4);  m_iow =                       2'd1;  m_oad = (m_adr + m_cnt - 4) % MSZ;  end  // Read Data Bytes
  8'h0b   : begin  m_ien = 1'b0;  m_oen = (m_cnt >= 5);  m_iow =                       2'd1;  m_oad = (m_adr + m_cnt - 5) % MSZ;  end  // Read Data Bytes at Higher Speed
  8'h3b   : begin  m_ien = 1'b0;  m_oen = (m_cnt >= 5);  m_iow = (m_cnt >= 5) ? 2'd2 : 2'd1;  m_oad = (m_adr + m_cnt - 5) % MSZ;  end  // Dual Output Fast Read
  8'hbb   : begin  m_ien = 1'b0;  m_oen = (m_cnt >= 5);  m_iow = (m_cnt >= 1) ? 2'd2 : 2'd1;  m_oad = (m_adr + m_cnt - 5) % MSZ;  end  // Dual Input/Output Fast Read
  8'h6b   : begin  m_ien = 1'b0;  m_oen = (m_cnt >= 5);  m_iow = (m_cnt >= 5) ? 2'd3 : 2'd1;  m_oad = (m_adr + m_cnt - 5) % MSZ;  end  // Quad Output Fast Read
  8'heb   : begin  m_ien = 1'b0;  m_oen = (m_cnt >= 5);  m_iow = (m_cnt >= 1) ? 2'd3 : 2'd1;  m_oad = (m_adr + m_cnt - 5) % MSZ;  end  // Quad Input/Output Fast Read
  // write memory instuctions
  8'h02   : begin  m_oen = 1'b0;  m_ien = (m_cnt >= 4);  m_iow =                       2'd1;  m_iad = (m_adr + m_cnt - 4) % MSZ;  end  // Page Program
  8'ha2   : begin  m_oen = 1'b0;  m_ien = (m_cnt >= 4);  m_iow = (m_cnt >= 4) ? 2'd2 : 2'd1;  m_iad = (m_adr + m_cnt - 4) % MSZ;  end  // Dual Input Fast Program
  8'hd2   : begin  m_oen = 1'b0;  m_ien = (m_cnt >= 4);  m_iow = (m_cnt >= 1) ? 2'd2 : 2'd1;  m_iad = (m_adr + m_cnt - 4) % MSZ;  end  // Dual Input Extended Fast Program
  8'h32   : begin  m_oen = 1'b0;  m_ien = (m_cnt >= 4);  m_iow = (m_cnt >= 4) ? 2'd3 : 2'd1;  m_iad = (m_adr + m_cnt - 4) % MSZ;  end  // Quad Input Fast Program
  8'h12   : begin  m_oen = 1'b0;  m_ien = (m_cnt >= 4);  m_iow = (m_cnt >= 1) ? 2'd3 : 2'd1;  m_iad = (m_adr + m_cnt - 4) % MSZ;  end  // Quad Input Extended Fast Program
  // undefined instructions
  default : begin  m_ien = 1'b0;  m_oen = 1'b0;          m_iow =                       2'd1;  m_iad = 32'hxxxxxxxx;
                                                                                              m_oad = 32'hxxxxxxxx;               end  //
endcase

////////////////////////////////////////////////////////////////////////////////
// memory                                                                     //
////////////////////////////////////////////////////////////////////////////////

// initialization from file
`ifndef verilator
integer f;  // file pointer
integer s;  // file status
initial begin
  f = $fopen(FBIN, "r");
  s = $fread(mem, f);
  s = $rewind(f);
      $fclose(f);
end
`else
initial begin
  $readmemh (FHEX, mem);
end
`else
`endif

// write to memory
always @ (posedge o_clk)
if (m_ien & m_byt)  mem [m_iad] <= i_dat;

// read from memory
assign m_rdt = mem [m_oad];

////////////////////////////////////////////////////////////////////////////////
// data output                                                                //
////////////////////////////////////////////////////////////////////////////////

// output data byte
assign o_dat = m_rdt;

// output mixer
always @ (*)
case (m_iow)
  2'd0 :  o_tmp = {3'bxxx,  o_dat[7-m_bit   ]};  // 3-wire
  2'd1 :  o_tmp = {3'bxxx,  o_dat[7-m_bit   ]};  // spi
  2'd2 :  o_tmp = {2'bxx ,  o_dat[6-m_bit+:2]};  // dual
  2'd3 :  o_tmp = {         o_dat[4-m_bit+:4]};  // quad
endcase

// output enable
always @ (*)
case (m_iow)
  2'd0 :  o_ena = m_oen ? 4'b0001 : 4'b0000;  // 3-wire
  2'd1 :  o_ena = m_oen ? 4'b0010 : 4'b0000;  // spi
  2'd2 :  o_ena = m_oen ? 4'b0011 : 4'b0000;  // dual
  2'd3 :  o_ena = m_oen ? 4'b1111 : 4'b0000;  // quad
endcase

// output data
assign mosi   = ~o_ena[0] ? 1'bz :                              o_tmp[0];
assign miso   = ~o_ena[1] ? 1'bz : (m_iow == 2'd1) ? o_tmp[0] : o_tmp[1];
assign wp_n   = ~o_ena[2] ? 1'bz :                              o_tmp[2];
assign hold_n = ~o_ena[3] ? 1'bz :                              o_tmp[3];

endmodule
