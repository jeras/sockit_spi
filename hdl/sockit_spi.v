////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  Copyright (C) 2008  Iztok Jeras                                           //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  This RTL is free hardware: you can redistribute it and/or modify          //
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

////////////////////////////////////////////////////////////////////////////////
// this file contains the system bus interface and static registers           //
////////////////////////////////////////////////////////////////////////////////

module spi #(
  parameter CFG_RST = 32'h00000000,  // configuration register reset value
  parameter CFG_MSK = 32'hffffffff,  // configuration register implementation mask
  parameter SDW     = 32,            // shift register data width
  parameter SSW     = 8              // slave select width
)(
  // system signals (used by the CPU interface)
  input  wire           clk,         // clock
  input  wire           rst,         // reset
  // CPU interface bus
  input  wire           bus_wen,     // write enable
  input  wire           bus_ren,     // read enable
  input  wire     [1:0] bus_adr,     // address
  input  wire    [31:0] bus_wdt,     // write data
  output wire    [31:0] bus_rdt,     // read data
  output wire           bus_wrq,     // wait request
  output wire           bus_irq,     // interrupt request
  // SPI signals (at a higher level should be connected to tristate IO pads)
  // serial clock
  input  wire           spi_sclk_i,  // input (clock loopback)
  output wire           spi_sclk_o,  // output
  output wire           spi_sclk_e,  // output enable
  // serial input output SIO[3:0] or {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  input  wire     [3:0] spi_sio_i,   // input
  output reg      [3:0] spi_sio_o,   // output
  output reg      [3:0] spi_sio_e,   // output enable
  // active low slave select signal
  output wire [SSW-1:0] spi_ss_i,    // input  (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_o,    // output (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_e     // output enable
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// bus interface signals
wire    [3:0] bus_dec;

// configuration registers
reg   [8-1:0] cfg_sso;  // slave select outputs
reg   [8-1:0] cfg_div;  // clock divider ratio
reg   [4-1:0] cfg_xip;  // clock divider ratio
reg           cfg_hle;  // hold output enable
reg           cfg_hlo;  // hold output
reg           cfg_wpe;  // write protect output enable
reg           cfg_wpo;  // write protect output
reg           cfg_coe;  // clock output enable
reg           cfg_sse;  // slave select output enable
reg   [2-1:0] cfg_iom;  // IO mode (0-3wire, 1-SPI, 2-duo, 3-quad)
reg           cfg_bit;  // bit mode
reg           cfg_dir;  // shift direction (0 - lsb first, 1 - msb first)
reg           cfg_pol;  // clock polarity
reg           cfg_pha;  // clock phase

// clock divider signals
reg   [8-1:0] div_cnt;  // clock divider counter
wire          div_byp;  // divider bypass
reg           div_clk;  // register storing the SCLK clock value (additional division by two)

// spi shift transfer control registers
reg           ctl_ssc;  // slave select clear
reg           ctl_sse;  // slave select clear
reg           ctl_oen;  // data output enable
reg     [7:0] ctl_cby;  // counter of bytes (default transfere units)
reg     [2:0] ctl_cbt;  // counter of shifted bits
wire          ctl_run;  // transfer running status

// serialization
reg     [3:0] ser_rgi;  // input register
reg [SDW-1:0] ser_dat;  // spi data shift register
reg     [3:0] ser_rgo;  // output register
wire    [3:0] ser_sio;  // output phase multiplexer

wire          clk_l;         // loopback clock

////////////////////////////////////////////////////////////////////////////////
// address decoder                                                            //
////////////////////////////////////////////////////////////////////////////////

assign bus_dec [0] = (bus_adr == 2'h0);  // data
assign bus_dec [1] = (bus_adr == 2'h1);  // control/status
assign bus_dec [2] = (bus_adr == 2'h2);  // configuratio
assign bus_dec [3] = (bus_adr == 2'h3);  // XIP base address

////////////////////////////////////////////////////////////////////////////////
// bus read access                                                            //
////////////////////////////////////////////////////////////////////////////////

// output data multiplexer
assign bus_rdt = bus_dec[0] ? ser_dat
               : bus_dec[1] ? {23'h000000,
                               ctl_ssc, ctl_cce, ctl_oen, ctl_cby}
               : bus_dec[2] ? {                           cfg_sso,
                                                          cfg_div,
                               cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo,
                                                          cfg_xip,
                               cfg_coe, cfg_sse,          cfg_iom,
                               cfg_bit, cfg_dir, cfg_pol, cfg_pha}
               : 32'hxxxxxxxx;

assign bus_wrq = 1'b0;
assign bus_irq = 1'b0;

////////////////////////////////////////////////////////////////////////////////
// configuration register                                                     //
////////////////////////////////////////////////////////////////////////////////

always @(posedge clk, posedge rst)
if (rst) begin
  {                           cfg_sso} <= CFG_RST [31:24];
  {                           cfg_div} <= CFG_RST [23:16];
  {cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo} <= CFG_RST [15:12];
  {                           cfg_xip} <= CFG_RST [11: 8];
  {cfg_coe, cfg_sse,          cfg_iom} <= CFG_RST [ 6: 4];
  {cfg_bit, cfg_dir, cfg_pol, cfg_pha} <= CFG_RST [ 3: 0];
end else if (bus_wen & bus_dec[2] & ~bus_wrq) begin
  {                           cfg_sso} <= bus_wdt [31:24];
  {                           cfg_div} <= bus_wdt [23:16];
  {cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo} <= bus_wdt [11: 8];
  {                           cfg_xip} <= bus_wdt [11: 8];
  {cfg_coe, cfg_sse,          cfg_iom} <= bus_wdt [ 6: 4];
  {cfg_bit, cfg_dir, cfg_pol, cfg_pha} <= bus_wdt [ 3: 0];
end

//////////////////////////////////////////////////////////////////////////////
// clock divider                                                            //
//////////////////////////////////////////////////////////////////////////////

// spi slave select
assign spi_ss_o = {SSW{ctl_sse}} & cfg_sso [SSW-1:0];
assign spi_ss_e = {SSW{cfg_sse}};

//////////////////////////////////////////////////////////////////////////////
// clock divider                                                            //
//////////////////////////////////////////////////////////////////////////////

// divider bypass bit
assign div_byp = cfg_div [5];

// clock counter
always @(posedge clk, posedge rst)
if (rst)
  div_cnt <= 'b0;
else begin
  if (~ctl_run | ~|div_cnt)
    div_cnt <= cfg_div ;
  else if (ctl_run)
    div_cnt <= div_cnt - 1;
end

// clock output register (divider by 2)
always @(posedge clk)
if (~ctl_run)
  div_clk <= cfg_pol;
else if (~|div_cnt)
  div_clk <= ~div_clk;

assign div_ena = div_byp ? 1 : ~|div_cnt & (div_clk ^ cfg_pol);

////////////////////////////////////////////////////////////////////////////////
// control/status registers (transfer counter and serial output enable)       //
////////////////////////////////////////////////////////////////////////////////

// bit counter
always @(posedge clk, posedge rst)
if (rst)                     ctl_cbt <= 3'd0;
else if (ctl_run & div_ena)  ctl_cbt <= ctl_cbt + 3'd1;

// transfer length counter
always @(posedge clk, posedge rst)
if (rst) begin
  ctl_ssc <= 1'b0;
  ctl_sse <= 1'b0;
  ctl_oen <= 1'b0;
  ctl_cby <= 8'd0;
end else begin
  // write from the CPU bus has priority
  if (bus_wen & bus_dec[1] & ~bus_wrq) begin
    ctl_ssc <= bus_wdt[   10];
    ctl_sse <= bus_wdt[    9];
    ctl_oen <= bus_wdt[    8];
    ctl_cby <= bus_wdt[ 7: 0];
  // decrement at the end of each transfer unit (byte by default)
  end else if (&ctl_cbt & div_ena) begin
    ctl_sse <= ctl_sse & ~((ctl_cby == 8'd1) & ctl_ssc);
    ctl_oen <= ctl_sse &  ~(ctl_cby == 8'd1)           ;
    ctl_cby <= ctl_cby - 8'd1;
  end
end

// TODO, should probably be a register
// spi transfer run status
assign ctl_run = |ctl_cby;

////////////////////////////////////////////////////////////////////////////////
// serialization                                                              //
////////////////////////////////////////////////////////////////////////////////

// input register
always @ (posedge clk)
if (ctl_run & div_ena & ~cfg_pha)  ser_rgi <= spi_sio_i;

// shift register implementation
always @ (posedge clk)
if (bus_wen & bus_dec[0] & ~bus_wrq)
  ser_dat <= bus_wdt; // TODO add fifo code
else if (ctl_run & div_ena) begin
  if (cfg_dir) begin
    case (cfg_iom)
      2'd0 :  ser_dat <= {ser_dat[SDW-1-1:0], cfg_pha ? spi_sio_i [  0] : ser_rgi [  0]};
      2'd1 :  ser_dat <= {ser_dat[SDW-1-1:0], cfg_pha ? spi_sio_i [1  ] : ser_rgi [1  ]};
      2'd2 :  ser_dat <= {ser_dat[SDW-2-1:0], cfg_pha ? spi_sio_i [1:0] : ser_rgi [1:0]};
      2'd3 :  ser_dat <= {ser_dat[SDW-4-1:0], cfg_pha ? spi_sio_i [3:0] : ser_rgi [3:0]};
    endcase
  end else begin
    case (cfg_iom)
      2'd0 :  ser_dat <= {cfg_pha ? spi_sio_i [0:0] : ser_rgi [0:0], ser_dat[SDW-1:1]};
      2'd1 :  ser_dat <= {cfg_pha ? spi_sio_i [0:0] : ser_rgi [0:0], ser_dat[SDW-1:1]};
      2'd2 :  ser_dat <= {cfg_pha ? spi_sio_i [1:0] : ser_rgi [1:0], ser_dat[SDW-1:2]};
      2'd3 :  ser_dat <= {cfg_pha ? spi_sio_i [3:0] : ser_rgi [3:0], ser_dat[SDW-1:4]};
    endcase
  end
end

// output register
always @ (posedge clk)
if (ctl_run & div_ena & cfg_pha)  ser_rgi <= ser_dat[SDW-4+:4];

// output phase multiplexer
assign ser_sio = cfg_pha ? ser_rgi : ser_dat[SDW-4+:4];

// output drivers
always @ (*) case (cfg_iom)
  2'd0 :  spi_sio_o = {cfg_hlo, cfg_wpo, 1'bx, ser_sio[  3]};
  2'd1 :  spi_sio_o = {cfg_hlo, cfg_wpo, 1'bx, ser_sio[  3]};
  2'd2 :  spi_sio_o = {cfg_hlo, cfg_wpo,       ser_sio[3:2]};
  2'd3 :  spi_sio_o = {                        ser_sio[3:0]};
endcase

assign ser_oen = ctl_oen;

// output enable
always @ (*) case (cfg_iom)
  2'd0 :  spi_sio_e = {cfg_hle, cfg_wpe,    1'b0, ser_oen};
  2'd1 :  spi_sio_e = {cfg_hle, cfg_wpe,    1'b0, ser_oen};
  2'd2 :  spi_sio_e = {cfg_hle, cfg_wpe, ser_oen, ser_oen};
  2'd3 :  spi_sio_e = {ser_oen, ser_oen, ser_oen, ser_oen};
endcase

// always @(posedge clk_l)
// if ( cfg_pha)  reg_o <= ser_o;
// 
// always @(posedge clk_l)
// if (~cfg_pha)  reg_i <= spi_mi;
// 
// // loop clock
// assign clk_l  = spi_sclk_i ^ cfg_pol;

// spi clock output pin
assign spi_sclk_o = div_byp ? cfg_pol ^ (ctl_run & ~clk) : div_clk;
assign spi_sclk_e = cfg_coe;

endmodule
