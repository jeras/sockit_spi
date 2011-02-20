////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  Copyright (C) 2011  Iztok Jeras                                           //
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

module sockit_spi #(
  parameter CTL_RST = 32'h00000000,  // control/status register reset value
  parameter CTL_MSK = 32'hffffffff,  // control/status register implementation mask
  parameter CFG_RST = 32'h00000000,  // configuration register reset value
  parameter CFG_MSK = 32'hffffffff,  // configuration register implementation mask
  parameter XIP_RST = 32'h00000000,  // XIP configuration register reset value
  parameter XIP_MSK = 32'h00000001,  // XIP configuration register implentation mask
  parameter NOP     = 32'h00000000,  // no operation instuction for the given CPU
  parameter XAW     = 24,            // XIP address width
  parameter SDW     = 32,            // shift register data width
  parameter SSW     =  8             // slave select width
)(
  // system signals (used by the CPU interface)
  input  wire           clk,         // clock
  input  wire           rst,         // reset
  // XIP interface bus
  input  wire           xip_ren,     // read enable
  input  wire [XAW-1:0] xip_adr,     // address
  output wire    [31:0] xip_rdt,     // read data
  output wire           xip_wrq,     // wait request
  output wire           xip_irq,     // interrupt request
  // registers interface bus
  input  wire           reg_wen,     // write enable
  input  wire           reg_ren,     // read enable
  input  wire     [1:0] reg_adr,     // address
  input  wire    [31:0] reg_wdt,     // write data
  output wire    [31:0] reg_rdt,     // read data
  output wire           reg_wrq,     // wait request
  output wire           reg_irq,     // interrupt request
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

// internal bus, finite state machine master
wire        bus_wen, fsm_wen;  // write enable
                               // read enable
wire        bus_adr, fsm_adr;  // address
wire [31:0] bus_wdt, fsm_wdt;  // write data
                               // read data
wire        bus_wrq, fsm_wrq;  // wait request

// configuration registers
wire    [31:0] cfg_reg;  // 32bit register
reg    [8-1:0] cfg_sso;  // slave select outputs
reg    [8-1:0] cfg_div;  // clock divider ratio
reg    [4-1:0] cfg_xip;  // clock divider ratio
reg            cfg_hle;  // hold output enable
reg            cfg_hlo;  // hold output
reg            cfg_wpe;  // write protect output enable
reg            cfg_wpo;  // write protect output
reg            cfg_coe;  // clock output enable
reg            cfg_sse;  // slave select output enable
reg            cfg_bit;  // bit mode
reg            cfg_dir;  // shift direction (0 - lsb first, 1 - msb first)
reg            cfg_pol;  // clock polarity
reg            cfg_pha;  // clock phase

// XIP configuration TODO
reg     [31:0] xip_reg;  // XIP configuration
wire           xip_ena;  // XIP configuration

// clock divider signals
reg    [8-1:0] div_cnt;  // clock divider counter
wire           div_byp;  // divider bypass
reg            div_clk;  // register storing the SCLK clock value (additional division by two)
wire           div_ena;  // divided clock enable pulse

// control registers
wire    [31:0] ctl_reg;  // 32bit register
reg            ctl_fio;  // fifo direction (0 - input, 1 - output)
reg            ctl_ssc;  // slave select clear
reg            ctl_sse;  // slave select enable
reg            ctl_ien;  // data input  enable
reg            ctl_oel;  // data output enable last
reg            ctl_oec;  // data output enable clear
reg            ctl_oen;  // data output enable
reg      [1:0] ctl_iow;  // IO width (0-3wire, 1-SPI, 2-duo, 3-quad)
reg     [11:0] ctl_cnt;  // counter of transfer units (nibbles by default)
reg      [1:0] ctl_btc;  // counter of shifted bits
reg      [1:0] ctl_btn;  // counter of shifted bits next (+1)

// status registers
reg            sts_beg;  // transfer begin pulse
reg            sts_run;  // transfer run status
reg            sts_nin;  // transfer nibble pulse // TODO
reg            sts_nib;  // transfer nibble pulse
reg            sts_smp;  // transfer sample pulse
reg            sts_end;  // transfer end pulse
reg            sts_ren;  // transfer read pulse
reg            sts_wdt;  // write cycle status
reg            sts_rdt;  // read  cycle status

// fifo buffer
reg      [8:0] buf_cnt;  // fifo load counter
reg  [SDW-1:0] buf_dat;  // fifo data register

// serialization
reg      [3:0] ser_dmi;  // data mixer input register
reg      [3:0] ser_dsi;  // data shift input register
reg      [3:0] ser_dpi;  // data shift phase synchronization
reg      [3:0] ser_dti;  // data shift input
reg  [SDW-1:0] ser_dat;  // data shift register
reg      [3:0] ser_dmo;  // data mixer output
reg      [3:0] ser_dme;  // data mixer output enable

// input, output, enable
reg  [SSW-1:0] ioe_sso;  // slave select output register
reg      [3:0] ioe_dri;  // direct register input
reg      [3:0] ioe_pri;  // phase  register input
reg      [3:0] ioe_dro;  // direct register output
reg      [3:0] ioe_pro;  // phase  register output
reg      [3:0] ioe_dre;  // direct register output enable
reg      [3:0] ioe_pre;  // phase  register output enable

////////////////////////////////////////////////////////////////////////////////
// XIP, registers interface multiplexer                                       //
////////////////////////////////////////////////////////////////////////////////

// TODO
assign xip_ena = xip_reg[0];

sockit_spi_xip #(
.XAW      (XAW),      // bus address width
.NOP      (NOP)       // no operation instruction (returned on error)
) xip (
// system signals
.clk      (clk),      // clock
.rst      (rst),      // reset
// input bus (XIP requests)
.xip_ren  (xip_ren),  // read enable
.xip_adr  (xip_adr),  // address
.xip_rdt  (xip_rdt),  // read data
.xip_wrq  (xip_wrq),  // wait request
.xip_err  (       ),  // error interrupt
// output bus (interface to SPI master registers)
.fsm_wen  (fsm_wen),  // write enable
.fsm_adr  (fsm_adr),  // address
.fsm_wdt  (fsm_wdt),  // write data
.fsm_wrq  (bus_wrq),  // wait request
.fsm_rdt  (buf_dat),  // read data
.fsm_ctl  (ctl_reg),  // read control/status
// configuration
.adr_off  ()          // address offset
);

// data & controll register access multipleser between two busses
assign bus_wen = xip_ena ? fsm_wen : reg_wen & ~reg_adr[1];  // write enable
assign bus_adr = xip_ena ? fsm_adr : reg_adr[0];             // address
assign bus_wdt = xip_ena ? fsm_wdt : reg_wdt;                // write data

// register interface return signals
assign reg_rdt = reg_adr[1] ? (reg_adr[0] ? xip_reg : cfg_reg)
                            : (reg_adr[0] ? ctl_reg : buf_dat);  // read data
assign reg_wrq = reg_adr[1] ?                  1'b0 : bus_wrq;   // wait request

// wait request timing
assign bus_wrq = 1'b0;

////////////////////////////////////////////////////////////////////////////////
// interrupt request                                                          //
////////////////////////////////////////////////////////////////////////////////

assign reg_irq = 1'b0;

////////////////////////////////////////////////////////////////////////////////
// bus read register concatenations                                           //
////////////////////////////////////////////////////////////////////////////////

// control/status register read data
assign ctl_reg = {                           buf_cnt,
                           ctl_fio, ctl_ssc, ctl_sse,
                  ctl_ien, ctl_oel, ctl_oec, ctl_oen,
                  sts_rdt, sts_wdt,          ctl_iow,
                                             ctl_cnt};

// SPI configuration register
assign cfg_reg = {                           cfg_sso,
                                             cfg_div,
                                                4'h0,
                  cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo,
                  cfg_coe, cfg_sse,          ctl_iow,
                  cfg_bit, cfg_dir, cfg_pol, cfg_pha};

////////////////////////////////////////////////////////////////////////////////
// configuration registers                                                    //
////////////////////////////////////////////////////////////////////////////////

// SPI configuration
always @(posedge clk, posedge rst)
if (rst) begin
  {                           cfg_sso} <= CFG_RST [31:24];
  {                           cfg_div} <= CFG_RST [23:16];
  {cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo} <= CFG_RST [11: 8];
  {cfg_coe, cfg_sse}                   <= CFG_RST [ 7: 6];
  {cfg_bit, cfg_dir, cfg_pol, cfg_pha} <= CFG_RST [ 3: 0];
end else if (reg_wen & (reg_adr == 2'd2) & ~reg_wrq) begin
  {                           cfg_sso} <= bus_wdt [31:24];
  {                           cfg_div} <= bus_wdt [23:16];
  {cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo} <= bus_wdt [11: 8];
  {cfg_coe, cfg_sse}                   <= bus_wdt [ 7: 6];
  {cfg_bit, cfg_dir, cfg_pol, cfg_pha} <= bus_wdt [ 3: 0];
end

// XIP configuration
always @(posedge clk, posedge rst)
if (rst) begin
  xip_reg <= XIP_RST [31: 0];
end else if (reg_wen & (reg_adr == 2'd3) & ~reg_wrq) begin
  xip_reg <= reg_wdt;
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
  if (~sts_run | ~|div_cnt)
    div_cnt <= cfg_div ;
  else if (sts_run)
    div_cnt <= div_cnt - 1;
end

// clock output register (divider by 2)
always @(posedge clk)
if (~sts_run)
  div_clk <= cfg_pol;
else if (~|div_cnt)
  div_clk <= ~div_clk;

assign div_ena = div_byp ? 1 : ~|div_cnt & (div_clk ^ cfg_pol);

////////////////////////////////////////////////////////////////////////////////
// control register                                                           //
////////////////////////////////////////////////////////////////////////////////

// transfer length counter
always @(posedge clk, posedge rst)
if (rst) begin
  ctl_fio <=  1'b0;
  ctl_ssc <=  1'b0;
  ctl_sse <=  1'b0;
  ctl_ien <=  1'b0;
  ctl_oel <=  1'b0;
  ctl_oec <=  1'b0;
  ctl_oen <=  1'b0;
  ctl_iow <=  2'd0;
  ctl_cnt <= 12'd0;
end else begin
  // write from the CPU bus has priority
  if (bus_wen & bus_adr & ~bus_wrq) begin
    ctl_fio <= bus_wdt[22   ];
    ctl_ssc <= bus_wdt[21   ];
    ctl_sse <= bus_wdt[20   ];
    ctl_ien <= bus_wdt[19   ];
    ctl_oel <= bus_wdt[18   ];
    ctl_oec <= bus_wdt[17   ];
    ctl_oen <= bus_wdt[16   ];
    ctl_iow <= bus_wdt[13:12];
    ctl_cnt <= bus_wdt[11: 0];
  // decrement at the end of each transfer unit (nibble by default)
  end else if (sts_nib) begin
    ctl_cnt <= ctl_cnt - 12'd1;
  end
end

////////////////////////////////////////////////////////////////////////////////
// status registers                                                           //
////////////////////////////////////////////////////////////////////////////////

// bit counter
always @(posedge clk, posedge rst)
if (rst)           ctl_btc <= 2'd0;
else if (sts_run)  ctl_btc <= ctl_btn;

// bit counter next
always @ (*)
begin
  case (ctl_iow)
    2'd0 :  ctl_btn = ctl_btc + 2'd1;  // 3-wire
    2'd1 :  ctl_btn = ctl_btc + 2'd1;  // spi
    2'd2 :  ctl_btn = ctl_btc + 2'd2;  // dual
    2'd3 :  ctl_btn = ctl_btc + 2'd0;  // quad (increment by 4)
  endcase
end

// nibble end next pulse
always @ (*)
begin
  case (ctl_iow)
    2'd0 :  sts_nin = &ctl_btn[1:0];  // 3-wire
    2'd1 :  sts_nin = &ctl_btn[1:0];  // spi
    2'd2 :  sts_nin = &ctl_btn[1  ];  // dual
    2'd3 :  sts_nin =          1'b1;  // quad
  endcase
end

// nibble end pulse
always @(posedge clk, posedge rst)
if (rst)  sts_nib <= 1'b0;
else      sts_nib <= sts_nin & (sts_run | (ctl_iow == 2'd3) & sts_beg) & ~sts_end;  // TODO pipelining

// sample pulse
always @(posedge clk, posedge rst)
if (rst)  sts_smp <= 1'b0;
else      sts_smp <= sts_nib;

// spi transfer beginning pulse
always @ (posedge clk, posedge rst)
if (rst)  sts_beg <= 1'b0;
else      sts_beg <= bus_wen & bus_adr & ~bus_wrq & |bus_wdt[11:0];

// spi transfer run status
always @ (posedge clk, posedge rst)
if (rst)  sts_run <= 1'b0;
else      sts_run <= sts_beg | sts_run & ~sts_end;

// spi transfer end pulse
always @ (posedge clk, posedge rst)
if (rst)  sts_end <= 1'b0;
else      sts_end <= sts_nin & (ctl_cnt == ((ctl_iow == 2'd3) ? 12'd2 : 12'd1));

// read enable pulse
always @ (posedge clk, posedge rst)
if (rst)  sts_ren <= 1'b0;
else      sts_ren <= sts_end;

// status registers
always @ (posedge clk, posedge rst)
if (rst) begin
  sts_wdt <= 1'b0;
  sts_rdt <= 1'b0;
end else begin
  if (bus_wen & bus_adr & ~bus_wrq & |bus_wdt[11:0]) begin
//    sts_wdt <= bus_wdt[16];
//    sts_rdt <= bus_wdt[18];
    sts_wdt <= 1'b1;
    sts_rdt <= 1'b1;
  end else begin
    if ((ctl_cnt == 12'd1) & sts_nin) sts_wdt <= 1'b0;
    if (sts_end)                      sts_rdt <= 1'b0;
  end
end

////////////////////////////////////////////////////////////////////////////////
// fifo buffer                                                                //
////////////////////////////////////////////////////////////////////////////////

initial buf_cnt = 9'd0;

// shift register implementation
always @ (posedge clk)
if (bus_wen & ~bus_adr & ~bus_wrq)
  buf_dat <= bus_wdt; // TODO add fifo code
else if (sts_ren) begin
  buf_dat <= cfg_dir ? {         ser_dat[SDW-4-1:0], ser_dmi}   // MSB first
                     : {ser_dmi, ser_dat[SDW  -1:4]         };  // LSB first
end

////////////////////////////////////////////////////////////////////////////////
// serialization                                                              //
////////////////////////////////////////////////////////////////////////////////

// input mixer
always @ (*)
begin
  case (ctl_iow)
    2'd0 :  ser_dmi = {ser_dsi[2:0], ioe_dri[  0]};  // 3-wire
    2'd1 :  ser_dmi = {ser_dsi[2:0], ioe_dri[  1]};  // spi
    2'd2 :  ser_dmi = {ser_dsi[1:0], ioe_dri[1:0]};  // dual
    2'd3 :  ser_dmi = {              ioe_dri[3:0]};  // quad
  endcase
end

// input shift register
always @ (posedge clk)
if (sts_run & ctl_ien)  ser_dsi <= ser_dmi;

// input phase register
always @ (posedge clk)
if (sts_run & ctl_ien) begin
  case (ctl_iow)
    2'd0 :  if (ctl_btc[1:0] == 2'b00)  ser_dpi <= ser_dmi;
    2'd1 :  if (ctl_btc[1:0] == 2'b00)  ser_dpi <= ser_dmi;
    2'd2 :  if (ctl_btc[1  ] == 1'b0 )  ser_dpi <= ser_dmi;
    2'd3 :                              ser_dpi <= ser_dmi;
  endcase
end

// input shifter retiming
always @ (*)
begin
  case (ctl_iow)
    2'd0 :  ser_dti = ser_dpi;
    2'd1 :  ser_dti = ser_dpi;
    2'd2 :  ser_dti = ser_dmi;
    2'd3 :  ser_dti = ser_dmi;
  endcase
end

// shift register (nibble sized shifts)
always @ (posedge clk)
if   (sts_beg)  ser_dat <=           buf_dat                     ;  // par. load
else if (sts_run & sts_nin) begin
  if (cfg_dir)  ser_dat <= {         ser_dat[SDW-4-1:0], ser_dti};  // MSB first
  else          ser_dat <= {ser_dti, ser_dat[SDW  -1:4]         };  // LSB first
end

// output mixer
always @ (*)
if (sts_beg) begin
  case (ctl_iow)                                      // MSB first                        LSB first
    2'd0 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? buf_dat[SDW-1             +:1] : buf_dat[0           +:1]};
    2'd1 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? buf_dat[SDW-1             +:1] : buf_dat[0           +:1]};
    2'd2 :  ser_dmo = {cfg_hlo, cfg_wpo,       cfg_dir ? buf_dat[SDW-2             +:2] : buf_dat[0           +:2]};
    2'd3 :  ser_dmo = {                        cfg_dir ? buf_dat[SDW-4             +:4] : buf_dat[0           +:4]};
  endcase
end else begin
  case (ctl_iow)                                      // MSB first                        LSB first
    2'd0 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? ser_dat[SDW-1-ctl_btn[1:0]+:1] : ser_dat[ctl_btn[1:0]+:1]};
    2'd1 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? ser_dat[SDW-1-ctl_btn[1:0]+:1] : ser_dat[ctl_btn[1:0]+:1]};
    2'd2 :  ser_dmo = {cfg_hlo, cfg_wpo,       cfg_dir ? ser_dat[SDW-2-ctl_btn[1]*2+:2] : ser_dat[ctl_btn[1]*2+:2]};
    2'd3 :  ser_dmo = {                        cfg_dir ? ser_dat[SDW-8-0           +:4] : ser_dat[0           +:4]}; // this probably only works with divider bypass
  endcase
end

// output enable mixer
always @ (*)
begin
  case (ctl_iow)
    2'd0 :  ser_dme = {cfg_hle, cfg_wpe, 1'b0, sts_beg ? ctl_oen : ctl_oen & ~ctl_oec  };
    2'd1 :  ser_dme = {cfg_hle, cfg_wpe, 1'b0, sts_beg ? ctl_oen : ctl_oen & ~ctl_oec  };
    2'd2 :  ser_dme = {cfg_hle, cfg_wpe,    {2{sts_beg ? ctl_oen : ctl_oen & ~ctl_oec}}};
    2'd3 :  ser_dme = {                     {4{sts_beg ? ctl_oen : ctl_oen & ~ctl_oec}}};
  endcase
end

////////////////////////////////////////////////////////////////////////////////
// slave select, clock, data (input, output, enable)                          //
////////////////////////////////////////////////////////////////////////////////

// spi slave select
always @ (posedge clk, posedge rst)
if (rst)             ioe_sso <= {SSW{1'b0}};
else begin
  if      (sts_beg)  ioe_sso <= {SSW{ ctl_sse}} & cfg_sso [SSW-1:0];
  else if (sts_end)  ioe_sso <= {SSW{~ctl_ssc}} & ioe_sso;
end

assign spi_ss_o =      ioe_sso  ;
assign spi_ss_e = {SSW{cfg_sse}};

// spi clock output pin
assign spi_sclk_o = div_byp ? sts_run & (cfg_pol ^ ~clk) : div_clk;
assign spi_sclk_e = cfg_coe;


// phase register input
always @ (negedge clk)
if (~cfg_pha)  ioe_pri <= spi_sio_i;

// phase multiplexer input
// direct register input
always @ (posedge clk)
ioe_dri <= cfg_pha ? ioe_pri : spi_sio_i;


// direct register output
always @ (posedge clk)
ioe_dro <= ser_dmo;

// phase register output
always @ (negedge clk)
if  (cfg_pha)  ioe_pro <= ioe_dro;

// phase multiplexer output
assign spi_sio_o = cfg_pha ? ioe_pro : ioe_dro;


// direct register output enable
always @ (posedge clk, posedge rst)
if  (rst)                ioe_dre <= 4'b0000;
else
if  (sts_beg | sts_end)  ioe_dre <= ser_dme;

// phase register output enable
always @ (negedge clk, posedge rst)
if  (rst)      ioe_pre <= 4'b0000;
else
if  (cfg_pha)  ioe_pre <= ioe_dre;

// phase multiplexer output enable
assign spi_sio_e = cfg_pha ? ioe_pre : ioe_dre;

endmodule
