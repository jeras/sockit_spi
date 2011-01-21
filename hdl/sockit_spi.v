//////////////////////////////////////////////////////////////////////////////
//                                                                          //
//  Minimalistic SPI (3 wire) interface with Zbus interface                 //
//                                                                          //
//  Copyright (C) 2008  Iztok Jeras                                         //
//                                                                          //
//////////////////////////////////////////////////////////////////////////////
//                                                                          //
//  This RTL is free hardware: you can redistribute it and/or modify        //
//  it under the terms of the GNU Lesser General Public License             //
//  as published by the Free Software Foundation, either                    //
//  version 3 of the License, or (at your option) any later version.        //
//                                                                          //
//  This RTL is distributed in the hope that it will be useful,             //
//  but WITHOUT ANY WARRANTY; without even the implied warranty of          //
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           //
//  GNU General Public License for more details.                            //
//                                                                          //
//  You should have received a copy of the GNU General Public License       //
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.   //
//                                                                          //
//////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////
// this file contains the system bus interface and static registers         //
//////////////////////////////////////////////////////////////////////////////

module spi #(
  // SPI slave select paramaters
  parameter SSW = 8,         // slave select register width
  // SPI interface configuration parameters
  parameter CFG_bit   =  0,  // select bit mode instead of byte mode by default
  parameter CFG_3wr   =  0,  // duplex type (0 - SPI full duplex, 1 - 3WIRE half duplex (MOSI is shared))
  parameter CFG_oen   =  0,  // MOSI output enable after reset
  parameter CFG_dir   =  1,  // shift direction (0 - LSB first, 1 - MSB first)
  parameter CFG_cpol  =  0,  // clock polarity
  parameter CFG_cpha  =  0,  // clock phase
  // SPI clock divider parameters
  parameter PAR_cd_en =  1,  // clock divider enable (0 - use full system clock, 1 - use divider)
  parameter PAR_cd_ri =  1,  // clock divider register inplement (otherwise the default clock division factor is used)
  parameter DRW =  8,  // clock divider register width
  parameter DR0 =  0   // default clock division factor
)(
  // system signals (used by the CPU interface)
  input  wire           clk,
  input  wire           rst,
  // CPU interface bus
  input  wire           bus_wen,  // write enable
  input  wire           bus_ren,  // read enable
  input  wire     [1:0] bus_adr,  // address
  input  wire    [31:0] bus_wdt,  // write data
  output wire    [31:0] bus_rdt,  // read data
  output wire           bus_wrq,  // wait request
  output wire           bus_irq,  // interrupt request
  // SPI signals (at a higher level should be connected to tristate IO pads)
  // serial clock
  input  wire           spi_sclk_i,  // input (clock loopback)
  output wire           spi_sclk_o,  // output
  output wire           spi_sclk_e,  // output enable
  // serial input output SIO[3:0] or {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  input  wire     [3:0] spi_sio_i,   // input (clock loopback)
  output wire     [3:0] spi_sio_o,   // output
  output wire     [3:0] spi_sio_e,   // output enable
  // active low slave select signal
  output wire [SSW-1:0] spi_ss_n
);

//////////////////////////////////////////////////////////////////////////////
// local signals                                                            //
//////////////////////////////////////////////////////////////////////////////

// clock divider signals
reg  [DRW-1:0] div_cnt;  // clock divider counter
reg  [DRW-1:0] reg_div;  // register holding the requested clock division ratio
wire           div_byp;
reg            div_clk;  // register storing the SCLK clock value (additional division by two)

// spi shifter signals
reg  [32-1:0] reg_s;           // spi data shift register
reg  reg_i, reg_o;             // spi input-sampling to output-change phase shift registers
wire ser_i, ser_o;             // shifter serial input and output multiplexed signals
wire spi_mi;                   //
wire clk_l;                    // loopback clock

// spi slave select signals
reg  [SSW-1:0] reg_ss;         // active high slave select register

// spi configuration registers (shift direction, clock polarity and phase, 3 wire option)
reg  cfg_bit, cfg_3wr, cfg_oen, cfg_dir, cfg_cpol, cfg_cpha;

// spi shift transfer control registers
reg    [2:0] cnt_bit;  // counter of shifted bits
reg          ctl_ss;   // slave select enable register
reg    [7:0] ctl_cnb;  // counter of transfered data units (bytes by defoult)
wire         ctl_run;  // transfer running status


//////////////////////////////////////////////////////////////////////////////
// bus access implementation (generalisation of wishbone bus signals)       //
//////////////////////////////////////////////////////////////////////////////

// output data multiplexer
assign bus_rdt = (bus_adr == 2'h0) ? {{16-SSW{1'b0}}, reg_ss, {16-DRW{1'b0}}, reg_div} :
                 (bus_adr == 2'h1) ? {cfg_bit, cfg_3wr, cfg_oen, cfg_dir, cfg_cpol, cfg_cpha} :
                 (bus_adr == 2'h2) ? {24'h000000, ctl_cnb}:
                                     reg_s;

assign bus_wrq = 1'b0;
assign bus_irq   = 1'b0;

//////////////////////////////////////////////////////////////////////////////
// clock divider                                                            //
//////////////////////////////////////////////////////////////////////////////

// clock division factor number register
always @(posedge clk, posedge rst)
if (rst)
  reg_div <= DR0;
else if (bus_wen & (bus_adr == 0) & ~bus_wrq)
  reg_div <= bus_wdt[DRW-1:0];

// divider bypass bit
assign div_byp = reg_div[7];

// clock counter
always @(posedge clk, posedge rst)
if (rst)
  div_cnt <= 'b0;
else begin
  if (~ctl_run | ~|div_cnt)
    div_cnt <= reg_div;
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

//////////////////////////////////////////////////////////////////////////////
// configuration registers                                                  //
//////////////////////////////////////////////////////////////////////////////

always @(posedge clk, posedge rst)
if (rst) begin
  cfg_bit  <= CFG_bit;
  cfg_3wr  <= CFG_3wr;
  cfg_oen  <= CFG_oen;
  cfg_dir  <= CFG_dir;
  cfg_cpol <= CFG_cpol;
  cfg_cpha <= CFG_cpha;
end else if (bus_wen & (bus_adr == 1) & ~bus_wrq) begin
  cfg_bit  <= bus_wdt [5     ];
  cfg_3wr  <= bus_wdt [ 4    ];
  cfg_oen  <= bus_wdt [  3   ];
  cfg_dir  <= bus_wdt [   2  ];
  cfg_cpol <= bus_wdt [    1 ];
  cfg_cpha <= bus_wdt [     0];
end

//////////////////////////////////////////////////////////////////////////////
// control registers (transfer counter and serial output enable)            //
//////////////////////////////////////////////////////////////////////////////

// bit counter
always @(posedge clk, posedge rst)
if (rst)
  cnt_bit <= 0;
else if (ctl_run & div_ena)
  cnt_bit <= cnt_bit + 1;

// chip select enable
always @(posedge clk, posedge rst)
if (rst)
  ctl_ss <= 0;
else begin
  // write from the CPU bus has priority
  if (bus_wen & (bus_adr == 2) & ~bus_wrq)
    ctl_ss <= bus_wdt[31];
end

// transfer length counter
always @(posedge clk, posedge rst)
if (rst)
  ctl_cnb <= 0;
else begin
  // write from the CPU bus has priority
  if (bus_wen & (bus_adr == 2) & ~bus_wrq)
    ctl_cnb <= bus_wdt[7:0];
  // decrement at the end of each transfer unit (byte by default)
  else if (&cnt_bit & div_ena)
    ctl_cnb <= ctl_cnb - 1;
end

// spi transfer run status
assign ctl_run = |ctl_cnb;

//////////////////////////////////////////////////////////////////////////////
// spi slave select                                                         //
//////////////////////////////////////////////////////////////////////////////

always @(posedge clk, posedge rst)
if (rst)
  reg_ss <= 'b0;
else if (bus_wen & (bus_adr == 0) & ~bus_wrq)
  reg_ss <= bus_wdt [32-SSW-1:16];

assign spi_ss_n = ctl_ss ? ~reg_ss : ~{SSW{1'b0}};

//////////////////////////////////////////////////////////////////////////////
// spi shift register                                                       //
//////////////////////////////////////////////////////////////////////////////

// shift register implementation
always @(posedge clk)
if (bus_wen & (bus_adr == 3) & ~bus_wrq) begin
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
assign spi_sio_e[0] = cfg_oen;

// temporary IO handler

assign spi_sclk_e     = 1'b1;
assign spi_sio_o[3:1] = 3'b11x;
assign spi_sio_e[3:1] = 3'b110;


endmodule
