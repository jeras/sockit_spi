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
  output wire     [3:0] spi_sio_o,   // output
  output wire     [3:0] spi_sio_e,   // output enable
  // active low slave select signal
  output wire [SSW-1:0] spi_ss_i,    // input  (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_o,    // output (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_e     // output enable
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// bus interface signals
wire     [3:0] bus_dec;

// configuration registers
reg    [8-1:0] cfg_sse;     // slave select output enable
reg    [8-1:0] cfg_sso;     // slave select output (active high)
reg    [6-1:0] cfg_div;     // clock divider ratio
reg    [2-1:0] cfg_xip;     // clock divider ratio
reg            cfg_halt_e;  // hold output enable
reg            cfg_halt_o;  // halt output
reg            cfg_wp_e;    // write protect output enable
reg            cfg_wp_o;    // write protect output
reg            cfg_bit;     // bit mode
reg            cfg_dir;     // shift direction (0 - lsb first, 1 - msb first)
reg            cfg_cpol;    // clock polarity
reg            cfg_cpha;    // clock shift

// clock divider signals
reg    [8-1:0] div_cnt;  // clock divider counter
wire           div_byp;
reg            div_clk;  // register storing the SCLK clock value (additional division by two)

// spi shifter signals
reg  [32-1:0] reg_s;           // spi data shift register
reg  reg_i, reg_o;             // spi input-sampling to output-change phase shift registers
wire ser_i, ser_o;             // shifter serial input and output multiplexed signals
wire spi_mi;                   //
wire clk_l;                    // loopback clock

// spi shift transfer control registers
reg          ctl_oen;  // 
reg    [7:0] ctl_cnb;  // counter of transfered data units (bytes by default)
reg    [2:0] cnt_bit;  // counter of shifted bits
wire         ctl_run;  // transfer running status

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
assign bus_rdt = bus_dec[0] ? reg_s :
                 bus_dec[1] ? {23'h000000, ctl_oen, ctl_cnb} :
                 bus_dec[2] ? {cfg_sse, cfg_sso, cfg_div, cfg_xip,
                               cfg_halt_e, cfg_wp_e, cfg_halt_o, cfg_wp_o,
                               cfg_bit, cfg_dir, cfg_cpol, cfg_cpha}
                             : 32'hxxxxxxxx;

assign bus_wrq = 1'b0;
assign bus_irq = 1'b0;

////////////////////////////////////////////////////////////////////////////////
// configuration register                                                     //
////////////////////////////////////////////////////////////////////////////////

always @(posedge clk, posedge rst)
if (rst) begin
  {cfg_sse, cfg_sso, cfg_div, cfg_xip}         <= CFG_RST [31: 8];
  {cfg_halt_e, cfg_wp_e, cfg_halt_o, cfg_wp_o} <= CFG_RST [ 7: 4];
  {cfg_bit, cfg_dir, cfg_cpol, cfg_cpha}       <= CFG_RST [ 3: 0];
end else if (bus_wen & bus_dec[2] & ~bus_wrq) begin
  {cfg_sse, cfg_sso, cfg_div, cfg_xip}         <= bus_wdt [31: 8];
  {cfg_halt_e, cfg_wp_e, cfg_halt_o, cfg_wp_o} <= bus_wdt [ 7: 4];
  {cfg_bit, cfg_dir, cfg_cpol, cfg_cpha}       <= bus_wdt [ 3: 0];
end

// spi slave select
assign spi_ss_o = cfg_sso [SSW-1:0];
assign spi_ss_e = cfg_sse [SSW-1:0];

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
  div_clk <= cfg_cpol;
else if (~|div_cnt)
  div_clk <= ~div_clk;

assign div_ena = div_byp ? 1 : ~|div_cnt & (div_clk ^ cfg_cpol);

////////////////////////////////////////////////////////////////////////////////
// control/status registers (transfer counter and serial output enable)       //
////////////////////////////////////////////////////////////////////////////////

// bit counter
always @(posedge clk, posedge rst)
if (rst)
  cnt_bit <= 0;
else if (ctl_run & div_ena)
  cnt_bit <= cnt_bit + 1;

// transfer length counter
always @(posedge clk, posedge rst)
if (rst) begin
  ctl_oen <= 1'b0;
  ctl_cnb <=  'd0;
end else begin
  // write from the CPU bus has priority
  if (bus_wen & bus_dec[1] & ~bus_wrq) begin
    ctl_oen <= bus_wdt[    8];
    ctl_cnb <= bus_wdt[ 7: 0];
  // decrement at the end of each transfer unit (byte by default)
  end else if (&cnt_bit & div_ena) begin
    ctl_oen <= 1'b1;
    ctl_cnb <= ctl_cnb - 1;
  end
end

// spi transfer run status
assign ctl_run = |ctl_cnb;

////////////////////////////////////////////////////////////////////////////////
// spi shift register                                                         //
////////////////////////////////////////////////////////////////////////////////

// shift register implementation
always @(posedge clk)
if (bus_wen & bus_dec[0] & ~bus_wrq) begin
  reg_s <= bus_wdt; // TODO add fifo code
end else if (ctl_run & div_ena) begin
  if (cfg_dir)  reg_s <= {reg_s [30:0], ser_i};
  else          reg_s <= {ser_i, reg_s [31:1]};
end

// the serial output from the shift register depends on the direction of shifting
assign ser_o  = (cfg_dir) ? reg_s [31] : reg_s [0];

always @(posedge clk_l)
if ( cfg_cpha)  reg_o <= ser_o;

always @(posedge clk_l)
if (~cfg_cpha)  reg_i <= spi_mi;

// spi clock output pin
assign spi_sclk_o = div_byp ? cfg_cpol ^ (ctl_run & ~clk) : div_clk;

// loop clock
assign clk_l  = spi_sclk_i ^ cfg_cpol;

// the serial input depends on the used protocol (SPI, 3 wire)
assign spi_mi   = cfg_3wr ? spi_sio_i[0] : spi_sio_i[1];

assign ser_i    = ~cfg_cpha ? reg_i : spi_mi;
assign spi_sio_o[0] = ~cfg_cpha ? ser_o : reg_o;
assign spi_sio_e[0] = ctl_oen;

// temporary IO handler

assign spi_sclk_e   = 1'b1;
assign spi_sio_o[1] = 1'bx;
assign spi_sio_e[1] = 1'b0;

assign spi_sio_o [3:2] = {cfg_halt_o, cfg_wp_o};
assign spi_sio_e [3:2] = {cfg_halt_e, cfg_wp_e};

endmodule
