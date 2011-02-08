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
  parameter CBW     =  8,            // counter of bytes width
  parameter SSW     =  8             // slave select width
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
reg    [8-1:0] cfg_sso;  // slave select outputs
reg    [8-1:0] cfg_div;  // clock divider ratio
reg    [4-1:0] cfg_xip;  // clock divider ratio
reg            cfg_hle;  // hold output enable
reg            cfg_hlo;  // hold output
reg            cfg_wpe;  // write protect output enable
reg            cfg_wpo;  // write protect output
reg            cfg_coe;  // clock output enable
reg            cfg_sse;  // slave select output enable
reg    [2-1:0] cfg_iow;  // IO width (0-3wire, 1-SPI, 2-duo, 3-quad)
reg            cfg_bit;  // bit mode
reg            cfg_dir;  // shift direction (0 - lsb first, 1 - msb first)
reg            cfg_pol;  // clock polarity
reg            cfg_pha;  // clock phase

// clock divider signals
reg    [8-1:0] div_cnt;  // clock divider counter
wire           div_byp;  // divider bypass
reg            div_clk;  // register storing the SCLK clock value (additional division by two)

// spi shift transfer control registers
reg            ctl_ssc;  // slave select clear
reg            ctl_sse;  // slave select enable
reg            ctl_ien;  // data input  enable
reg            ctl_oec;  // data output enable
reg            ctl_oen;  // data output enable
reg  [CBW-1:0] ctl_cby;  // counter of bytes (default transfere units)
wire [CBW-1:0] ctl_cbn;  // counter of bytes (default transfere units) next (+1)
reg      [2:0] ctl_btc;  // counter of shifted bits
wire     [2:0] ctl_btn;  // counter of shifted bits next (+1)
wire           ctl_beg;  // transfer begin   status
wire           ctl_run;  // transfer running status
wire           ctl_end;  // transfer end     status
wire           ctl_nib;  // transfer nibble  status
reg            ctl_ren;  // transfer read enable

// fifo buffer
reg  [SDW-1:0] buf_dat;

// serialization
reg      [3:0] ser_dmi;  // data mixer input register
reg      [3:0] ser_dsi;  // data shift input register
reg      [3:0] ser_dti;  // data shift synchronization
reg  [SDW-1:0] ser_dat;  // data shift register
reg      [3:0] ser_dmo;  // data mixer output
reg      [3:0] ser_dme;  // data mixer output enable

// serial IO
reg      [3:0] ser_pri;  // phase  register input
reg      [3:0] ser_dri;  // direct register input
reg      [3:0] ser_dro;  // direct register output
reg      [3:0] ser_pro;  // phase  register output
reg      [3:0] ser_dre;  // direct register output enable
reg      [3:0] ser_pre;  // phase  register output enable

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
               : bus_dec[1] ? {  8'h00,   6'h00, ctl_ssc, ctl_sse,
                                  1'b0, ctl_ien, ctl_oec, ctl_oen,
                               {16-CBW{1'b0}},            ctl_cby}
               : bus_dec[2] ? {                           cfg_sso,
                                                          cfg_div,
                               cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo,
                                                          cfg_xip,
                               cfg_coe, cfg_sse,          cfg_iow,
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
  {cfg_coe, cfg_sse,          cfg_iow} <= CFG_RST [ 7: 4];
  {cfg_bit, cfg_dir, cfg_pol, cfg_pha} <= CFG_RST [ 3: 0];
end else if (bus_wen & bus_dec[2] & ~bus_wrq) begin
  {                           cfg_sso} <= bus_wdt [31:24];
  {                           cfg_div} <= bus_wdt [23:16];
  {cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo} <= bus_wdt [15:12];
  {                           cfg_xip} <= bus_wdt [11: 8];
  {cfg_coe, cfg_sse,          cfg_iow} <= bus_wdt [ 7: 4];
  {cfg_bit, cfg_dir, cfg_pol, cfg_pha} <= bus_wdt [ 3: 0];
end

//////////////////////////////////////////////////////////////////////////////
// clock divider                                                            //
//////////////////////////////////////////////////////////////////////////////

// divider bypass bit
assign div_byp = ~|cfg_div;

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
if (rst)                     ctl_btc <= 3'd0;
else if (ctl_run & div_ena)  ctl_btc <= ctl_btn;

// bit next
assign ctl_btn = ctl_btc + 3'd1;

// transfer length counter
always @(posedge clk, posedge rst)
if (rst) begin
  ctl_ssc <= 1'b0;
  ctl_sse <= 1'b0;
  ctl_ien <= 1'b0;
  ctl_oec <= 1'b0;
  ctl_cby <=  'd0;
end else begin
  // write from the CPU bus has priority
  if (bus_wen & bus_dec[1] & ~bus_wrq) begin
    ctl_ssc <= bus_wdt[21     ];
    ctl_sse <= bus_wdt[ 20    ];
    ctl_ien <= bus_wdt[   18  ];
    ctl_oec <= bus_wdt[    17 ];
    ctl_cby <= bus_wdt[CBW-1:0];
  // decrement at the end of each transfer unit (byte by default)
  end else if (&ctl_btc & div_ena) begin
    ctl_sse <= ctl_sse & ~((ctl_cby == 'd1) & ctl_ssc);
    ctl_cby <= ctl_cby - 'd1;
  end
end

// spi transfer beginning
assign ctl_beg = bus_wen & bus_dec[1] & ~bus_wrq;

// TODO, should probably be a register
// spi transfer run status
assign ctl_run = |ctl_cby;

// TODO, should probably be a register
// spi transfer end
assign ctl_end = (ctl_cby == 8'd1) & (&ctl_btc | cfg_bit);

// read enable
always @ (posedge clk, posedge rst)
if (rst)  ctl_ren <= 1'b0;
else      ctl_ren <= ctl_end;

// nibble end
assign ctl_nib = &ctl_btn[1:0];

////////////////////////////////////////////////////////////////////////////////
// fifo buffer                                                                //
////////////////////////////////////////////////////////////////////////////////

// shift register implementation
always @ (posedge clk)
if (bus_wen & bus_dec[0] & ~bus_wrq)
  buf_dat <= bus_wdt; // TODO add fifo code
else if (ctl_ren) begin
  buf_dat <= cfg_dir ? {         ser_dat[SDW-4-1:0], ser_dmi}   // MSB first
                     : {ser_dmi, ser_dat[SDW  -1:4]         };  // LSB first
end

////////////////////////////////////////////////////////////////////////////////
// serialization                                                              //
////////////////////////////////////////////////////////////////////////////////

// input mixer
always @ (*)
begin
  case (cfg_iow)
    2'd0 :  ser_dmi = {ser_dsi[2:0], ser_dri[  0]};  // 3-wire
    2'd1 :  ser_dmi = {ser_dsi[2:0], ser_dri[  1]};  // spi
    2'd2 :  ser_dmi = {ser_dsi[1:0], ser_dri[1:0]};  // dual
    2'd3 :  ser_dmi = {              ser_dri[3:0]};  // quad
  endcase
end

// input shift register
always @ (posedge clk)
ser_dsi <= ser_dmi;

// input shifter retiming
always @ (posedge clk)
if (ctl_btc[1:0] == 2'b01)  ser_dti <= ser_dsi;

// shift register (nibble sized shifts)
always @ (posedge clk)
if   (ctl_beg)  ser_dat <=           buf_dat                     ;  // par. load
else if (ctl_run & ctl_nib & div_ena) begin
  if (cfg_dir)  ser_dat <= {         ser_dat[SDW-4-1:0], ser_dti};  // LSB first
  else          ser_dat <= {ser_dti, ser_dat[SDW  -1:4]         };  // MSB first
end

// output mixer
always @ (*)
if (~ctl_run) begin
  case (cfg_iow)                                      // MSB first                        LSB first
    2'd0 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? buf_dat[SDW-1             +:1] : buf_dat[0           +:1]};
    2'd1 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? buf_dat[SDW-1             +:1] : buf_dat[0           +:1]};
    2'd2 :  ser_dmo = {cfg_hlo, cfg_wpo,       cfg_dir ? buf_dat[SDW-2             +:2] : buf_dat[0           +:2]};
    2'd3 :  ser_dmo = {                        cfg_dir ? buf_dat[SDW-4             +:4] : buf_dat[0           +:4]};
  endcase
end else begin
  case (cfg_iow)                                      // MSB first                        LSB first
    2'd0 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? ser_dat[SDW-1-ctl_btn[1:0]+:1] : ser_dat[ctl_btn[1:0]+:1]};
    2'd1 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? ser_dat[SDW-1-ctl_btn[1:0]+:1] : ser_dat[ctl_btn[1:0]+:1]};
    2'd2 :  ser_dmo = {cfg_hlo, cfg_wpo,       cfg_dir ? ser_dat[SDW-2-ctl_btn[1]*2+:2] : ser_dat[ctl_btn[1]*2+:2]};
    2'd3 :  ser_dmo = {                        cfg_dir ? ser_dat[SDW-4-0           +:4] : ser_dat[0           +:4]};
  endcase
end

// output enable mixer
always @ (*)
begin
  case (cfg_iow)
    2'd0 :  ser_dme = {cfg_hle, cfg_wpe, 1'b0, ctl_beg ? bus_wdt[16] : ~ctl_oec};
    2'd1 :  ser_dme = {cfg_hle, cfg_wpe, 1'b0, ctl_beg ? bus_wdt[16] : ~ctl_oec};
    2'd2 :  ser_dme = {cfg_hle, cfg_wpe,       ctl_beg ? bus_wdt[16] : ~ctl_oec};
    2'd3 :  ser_dme = {                        ctl_beg ? bus_wdt[16] : ~ctl_oec};
  endcase
end

////////////////////////////////////////////////////////////////////////////////
// SPI slave select, clock, inputs and outputs                                //
////////////////////////////////////////////////////////////////////////////////

// spi slave select
assign spi_ss_o = {SSW{ctl_sse}} & cfg_sso [SSW-1:0];
assign spi_ss_e = {SSW{cfg_sse}};


// spi clock output pin
assign spi_sclk_o = div_byp ? ctl_run & (cfg_pol ^ ~clk) : div_clk;
assign spi_sclk_e = cfg_coe;


// phase register input
always @ (negedge clk)
if (~cfg_pha & div_ena)  ser_pri <= spi_sio_i;

// phase multiplexer input
// direct register input
always @ (posedge clk)
if            (div_ena)  ser_dri <= cfg_pha ? ser_pri : spi_sio_i;


// direct register output
always @ (posedge clk)
if            (div_ena)  ser_dro <= ser_dmo;

// phase register output
always @ (negedge clk)
if  (cfg_pha & div_ena)  ser_pro <= ser_dro;

// phase multiplexer output
assign spi_sio_o = cfg_pha ? ser_pro : ser_dro;


// direct register output enable
always @ (posedge clk, posedge rst)
if  (rst)                ser_dre <= 4'b0000;
else
if  (ctl_beg | ctl_end)  ser_dre <= ser_dme;

// phase register output enable
always @ (negedge clk, posedge rst)
if  (rst)                ser_pre <= 4'b0000;
else
if  (cfg_pha & div_ena)  ser_pre <= ser_dre;

// phase multiplexer output enable
assign spi_sio_e = cfg_pha ? ser_pre : ser_dre;

endmodule
