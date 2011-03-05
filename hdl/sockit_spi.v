////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  Copyright (C) 2008-2011  Iztok Jeras                                      //
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
  parameter XAW     =           24,  // XIP address width
  parameter SSW     =            8,  // slave select width
  parameter CDC     =         1'b0   // implement clock domain crossing
)(
  // system signals (used by the CPU interface)
  input  wire           clk_cpu,     // clock for CPU interface
  input  wire           rst_cpu,     // reset for CPU interface
  input  wire           clk_spi,     // clock for SPI IO
  input  wire           rst_spi,     // reset for SPI IO
  // XIP interface bus
  input  wire           xip_ren,     // read enable
  input  wire [XAW-1:0] xip_adr,     // address
  output wire    [31:0] xip_rdt,     // read data
  output wire           xip_wrq,     // wait request
  output wire           xip_err,     // error interrupt
  // registers interface bus
  input  wire           reg_wen,     // write enable
/* verilator lint_off UNUSED */
  input  wire           reg_ren,     // read enable
/* verilator lint_on  UNUSED */
  input  wire     [1:0] reg_adr,     // address
  input  wire    [31:0] reg_wdt,     // write data
  output wire    [31:0] reg_rdt,     // read data
  output wire           reg_wrq,     // wait request
  output wire           reg_irq,     // interrupt request
  // SPI signals (at a higher level should be connected to tristate IO pads)
  // serial clock
/* verilator lint_off UNUSED */
  input  wire           spi_sclk_i,  // input (clock loopback)
/* verilator lint_on  UNUSED */
  output wire           spi_sclk_o,  // output
  output wire           spi_sclk_e,  // output enable
  // serial input output SIO[3:0] or {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  input  wire     [3:0] spi_sio_i,   // input
  output wire     [3:0] spi_sio_o,   // output
  output wire     [3:0] spi_sio_e,   // output enable
  // active low slave select signal
  input  wire [SSW-1:0] spi_ss_i,    // input  (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_o,    // output (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_e     // output enable
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// register interface read data signals
wire    [31:0] reg_sts;  // read status
wire    [31:0] reg_cfg;  // read SPI configuration
wire    [31:0] reg_xip;  // read XIP configuration

// internal bus, finite state machine master
wire           bus_wen, fsm_wen;  // write enable
wire           bus_ren, fsm_ren;  // read  enable
wire           bus_adr, fsm_adr;  // address
wire    [31:0] bus_wdt, fsm_wdt;  // write data
wire    [31:0] bus_rdt         ;  // read data
wire           bus_wrq         ;  // wait request

// data and control/status register write/read access transfers
wire           bus_wtr_dat;  // write data register
wire           bus_rtr_dat;  // read  data register
wire           bus_wtr_ctl;  // write control register
wire           bus_rtr_ctl;  // read  control register

// data and control/status register write enable/data
reg     [31:0] bus_wdt_dat;  // data register write enable
wire           bus_wen_dat;  // data register write data
reg     [31:0] bus_wdt_ctl;  // control register write enable
wire           bus_wen_ctl;  // control register write data

// configuration registers
reg    [8-1:0] cfg_sso;  // slave select output
reg    [8-1:0] cfg_sse;  // slave select output enable
reg            cfg_hle;  // hold output enable
reg            cfg_hlo;  // hold output
reg            cfg_wpe;  // write protect output enable
reg            cfg_wpo;  // write protect output
reg            cfg_coe;  // clock output enable
reg            cfg_bit;  // bit mode
reg            cfg_dir;  // shift direction (0 - lsb first, 1 - msb first)
reg            cfg_pol;  // clock polarity
reg            cfg_pha;  // clock phase

// XIP configuration TODO
reg     [31:0] xip_reg;  // XIP configuration
wire           xip_ena;  // XIP configuration

// clock domain crossing, control register
reg      [1:0] cdc_cwe;  // clock domain CPU, control register write enable
reg      [1:0] cdc_cwt;  // clock domain CPU, control register write toggle
reg      [1:0] cds_cwt;  // clock domain SPI, control register write toggle
reg      [1:0] cds_cwe;  // clock domain SPI, control register write enable

// control registers
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

// cycle timing registers
reg            cyc_beg;  // transfer begin pulse
reg            cyc_run;  // transfer run status
reg            cyc_nin;  // transfer nibble pulse next
reg            cyc_nib;  // transfer nibble pulse (registered version of cyc_nin)
reg            cyc_end;  // transfer end pulse
reg            cyc_ren;  // transfer read pulse
// TODO
reg            cyc_wdt;  // write cycle status
reg            cyc_rdt;  // read  cycle status

// status signals
wire           sts_ctl;  // control register pipeline status
wire           sts_cyc;  // SPI cycle status
wire           sts_odt;  // data output pipeline status
wire           sts_idt;  // data  input pipeline status

// clock domain crossing, output data
reg      [1:0] cdc_doe;  // clock domain CPU, data output enable
reg      [1:0] cdc_dot;  // clock domain CPU, data output toggle
reg      [1:0] cds_dot;  // clock domain SPI, data output toggle
reg      [1:0] cds_doe;  // clock domain SPI, data output enable

// clock domain crossing, input data
reg      [1:0] cdc_die;  // clock domain CPU, data input enable
reg      [1:0] cdc_dit;  // clock domain CPU, data input toggle
reg      [1:0] cds_dit;  // clock domain SPI, data input toggle
reg      [1:0] cds_die;  // clock domain SPI, data input enable

// fifo buffer
reg     [31:0] buf_dat;  // fifo data register

// serialization
reg      [3:0] ser_dmi;  // data mixer input register
reg      [2:0] ser_dsi;  // data shift input register
reg      [3:0] ser_dpi;  // data shift phase synchronization
reg      [3:0] ser_dti;  // data shift input
reg     [31:0] ser_dat;  // data shift register
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
.clk      (clk_cpu),  // clock
.rst      (rst_cpu),  // reset
// input bus (XIP requests)
.xip_ren  (xip_ren),  // read enable
.xip_adr  (xip_adr),  // address
.xip_rdt  (xip_rdt),  // read data
.xip_wrq  (xip_wrq),  // wait request
.xip_err  (xip_err),  // error interrupt
// output bus (interface to SPI master registers)
.fsm_wen  (fsm_wen),  // write enable
.fsm_ren  (fsm_ren),  // read  enable
.fsm_adr  (fsm_adr),  // address
.fsm_wdt  (fsm_wdt),  // write data
.fsm_rdt  (buf_dat),  // read data
.fsm_wrq  (bus_wrq),  // wait request
// SPI master status
.sts_cyc  (sts_cyc),  // cycle status
// configuration
.adr_off  (xip_reg[XAW-1:8])  // address offset
);

// data & controll register access multiplexer between two busses
assign bus_wen = xip_ena ? fsm_wen : reg_wen & ~reg_adr[1];  // write enable
assign bus_ren = xip_ena ? fsm_ren : reg_ren & ~reg_adr[1];  // read  enable
assign bus_adr = xip_ena ? fsm_adr : reg_adr[0];             // address
assign bus_wdt = xip_ena ? fsm_wdt : reg_wdt;                // write data

// register interface return signals
assign reg_rdt = reg_adr[1] ? (reg_adr[0] ? reg_xip : reg_cfg)
                            : (reg_adr[0] ? reg_sts : bus_rdt);  // read data
assign reg_wrq = reg_adr[1] ?                  1'b0 : bus_wrq;   // wait request

// wait request timing
assign bus_wrq = 1'b0;

// control/status and data register write/read access transfers
assign bus_wtr_ctl = bus_wen &  bus_adr & ~bus_wrq;  // write control register
assign bus_rtr_ctl = bus_ren &  bus_adr & ~bus_wrq;  // read  control register
assign bus_wtr_dat = bus_wen & ~bus_adr & ~bus_wrq;  // write data register
assign bus_rtr_dat = bus_ren & ~bus_adr & ~bus_wrq;  // read  data register

////////////////////////////////////////////////////////////////////////////////
// SPI status, interrupt request                                              //
////////////////////////////////////////////////////////////////////////////////

assign reg_sts = {28'h0000000, sts_idt, sts_odt, sts_cyc, sts_ctl};

assign reg_irq = 1'b0;

////////////////////////////////////////////////////////////////////////////////
// configuration registers                                                    //
////////////////////////////////////////////////////////////////////////////////

// SPI configuration (read access)
assign reg_cfg = {                          spi_ss_i,
                                             cfg_sse,
                                                4'h0,
                  cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo,
                  cfg_coe,                      3'h0,
                  cfg_bit, cfg_dir, cfg_pol, cfg_pha};

// SPI configuration (write access)
always @(posedge clk_cpu, posedge rst_cpu)
if (rst_cpu) begin
  {                           cfg_sso} <= CFG_RST [31:24];
  {                           cfg_sse} <= CFG_RST [23:16];
  {cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo} <= CFG_RST [11: 8];
  {cfg_coe}                            <= CFG_RST [ 7   ];
  {cfg_bit, cfg_dir, cfg_pol, cfg_pha} <= CFG_RST [ 3: 0];
end else if (reg_wen & (reg_adr == 2'd2) & ~reg_wrq) begin
  {                           cfg_sso} <= reg_wdt [31:24];
  {                           cfg_sse} <= reg_wdt [23:16];
  {cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo} <= reg_wdt [11: 8];
  {cfg_coe}                            <= reg_wdt [ 7   ];
  {cfg_bit, cfg_dir, cfg_pol, cfg_pha} <= reg_wdt [ 3: 0];
end

// XIP configuration (read access)
assign reg_xip = xip_reg;

// XIP configuration
always @(posedge clk_cpu, posedge rst_cpu)
if (rst_cpu) begin
  xip_reg <= XIP_RST [31: 0];
end else if (reg_wen & (reg_adr == 2'd3) & ~reg_wrq) begin
  xip_reg <= reg_wdt;
end

////////////////////////////////////////////////////////////////////////////////
// data register/fifo                                                         //
////////////////////////////////////////////////////////////////////////////////

generate
if (CDC) begin

  // clock domain CPU, control register write toggle
  always @ (posedge clk_cpu, posedge rst_cpu)
  if (rst_cpu)  cdc_dot <= 2'b00;
  else          cdc_dot <= {cds_dot [0], cdc_dot [1] ^ bus_wtr_dat};

  // clock domain SPI, control register write toggle
  always @ (posedge clk_spi, posedge rst_spi)
  if (rst_spi)  cds_dot <= 2'b00;
  else          cds_dot <= {cdc_dot [0], cds_dot [1] ^ cyc_beg};

  // clock domain SPI, control register write register
  always @ (posedge clk_spi, posedge rst_spi)
  if (rst_spi)  cds_doe <= 1'b0;
  else          cds_doe <= 1'b0;

  // data registers write enable // TODO
  assign bus_wen_dat = ~cyc_run & (cds_dot [1] ^ cds_doe);

  // data registers write data
  always @ (posedge clk_cpu)
  if (bus_wtr_dat)  bus_wdt_dat <= bus_wdt;

end else begin

  // bus read data
  assign bus_rdt = buf_dat;

  // data registers write enable
  assign bus_wen_dat = bus_wtr_dat;

  // data registers write data
  always @ (*)
  bus_wdt_dat = bus_wdt;

end
endgenerate

// buffer for swapping write/read data with shift register
always @ (posedge clk_cpu)
if  (bus_wen_dat)  buf_dat <= bus_wdt_dat; // TODO add fifo code
else if (cyc_ren)  buf_dat <= cfg_dir ? {ser_dat[32-4-1:0], ser_dmi}   // MSB first
                                      : {ser_dmi, ser_dat[32  -1:4]};  // LSB first

////////////////////////////////////////////////////////////////////////////////
// control register clock domain crossing (optional)                          //
////////////////////////////////////////////////////////////////////////////////

generate
if (CDC) begin

  // status of control register pipeline
  assign sts_ctl = cdc_cwt [1] ^ cdc_cwe;

  // clock domain CPU, control register write register
  always @ (posedge clk_cpu, posedge rst_cpu)
  if (rst_cpu)  cdc_cwe <= 1'b0;
  else          cdc_cwe <= 1'b0;

  // clock domain CPU, control register write toggle
  always @ (posedge clk_cpu, posedge rst_cpu)
  if (rst_cpu)  cdc_cwt <= 2'b00;
  else          cdc_cwt <= {cds_cwt [0], cdc_cwt [1] ^ bus_wtr_ctl};

  // clock domain SPI, control register write toggle
  always @ (posedge clk_spi, posedge rst_spi)
  if (rst_spi)  cds_cwt <= 2'b00;
  else          cds_cwt <= {cdc_cwt [0], cds_cwt [1] ^ cyc_beg};

  // clock domain SPI, control register write register
  always @ (posedge clk_spi, posedge rst_spi)
  if (rst_spi)  cds_cwe <= 1'b0;
  else          cds_cwe <= 1'b0;

  // control registers write enable // TODO
  assign bus_wen_ctl = ~cyc_run & (cds_cwt [1] ^ cds_cwe);

  // control registers write data
  always @ (posedge clk_cpu)
  if (bus_wtr_ctl)  bus_wdt_ctl <= bus_wdt;

end else begin

  // control registers write enable
  assign bus_wen_ctl = bus_wtr_ctl;

  // control registers write data
  always @ (*)
  bus_wdt_ctl = bus_wdt;

end
endgenerate

////////////////////////////////////////////////////////////////////////////////
// control registers                                                          //
////////////////////////////////////////////////////////////////////////////////

// transfer length counter
always @(posedge clk_cpu, posedge rst_cpu)
if (rst_cpu) begin
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
  if (bus_wen_ctl) begin
    ctl_fio <= bus_wdt_ctl[22   ];
    ctl_ssc <= bus_wdt_ctl[21   ];
    ctl_sse <= bus_wdt_ctl[20   ];
    ctl_ien <= bus_wdt_ctl[19   ];
    ctl_oel <= bus_wdt_ctl[18   ];
    ctl_oec <= bus_wdt_ctl[17   ];
    ctl_oen <= bus_wdt_ctl[16   ];
    ctl_iow <= bus_wdt_ctl[13:12];
    ctl_cnt <= bus_wdt_ctl[11: 0];
  // decrement at the end of each transfer unit (nibble by default)
  end else if (cyc_nib) begin
    ctl_cnt <= ctl_cnt - 12'd1;
  end
end

////////////////////////////////////////////////////////////////////////////////
// status registers                                                           //
////////////////////////////////////////////////////////////////////////////////

// bit counter
always @(posedge clk_spi, posedge rst_spi)
if (rst_spi)       ctl_btc <= 2'd0;
else if (cyc_run)  ctl_btc <= ctl_btn;

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
    2'd0 :  cyc_nin = &ctl_btn[1:0];  // 3-wire
    2'd1 :  cyc_nin = &ctl_btn[1:0];  // spi
    2'd2 :  cyc_nin = &ctl_btn[1  ];  // dual
    2'd3 :  cyc_nin =          1'b1;  // quad
  endcase
end

// nibble end pulse
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_nib <= 1'b0;
else          cyc_nib <= cyc_nin & (cyc_run | (ctl_iow == 2'd3) & cyc_beg) & ~cyc_end;  // TODO pipelining

// spi transfer beginning pulse
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_beg <= 1'b0;
else          cyc_beg <= bus_wen_ctl;

// spi transfer run status
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_run <= 1'b0;
else      cyc_run <= cyc_beg | cyc_run & ~cyc_end;

// spi transfer end pulse
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_end <= 1'b0;
else          cyc_end <= cyc_nin & (ctl_cnt == ((ctl_iow == 2'd3) ? 12'd1 : 12'd0));

// read enable pulse
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_ren <= 1'b0;
else          cyc_ren <= cyc_end;

// status registers
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi) begin
  cyc_wdt <= 1'b0;
  cyc_rdt <= 1'b0;
end else begin
  if (bus_wen_ctl) begin
//    cyc_wdt <= bus_wdt_ctl[16];
//    cyc_rdt <= bus_wdt_ctl[18];
    cyc_wdt <= 1'b1;
    cyc_rdt <= 1'b1;
  end else begin
    if ((ctl_cnt == 12'd0) & cyc_nin) cyc_wdt <= 1'b0;
    if (cyc_end)                      cyc_rdt <= 1'b0;
  end
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
always @ (posedge clk_spi)
if (cyc_run & ctl_ien)  ser_dsi <= ser_dmi[2:0];

// input phase register
always @ (posedge clk_spi)
if (cyc_run & ctl_ien) begin
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
always @ (posedge clk_spi)
if   (cyc_beg)  ser_dat <=           buf_dat                     ;  // par. load
else if (cyc_run & cyc_nin) begin
  if (cfg_dir)  ser_dat <= {         ser_dat[32-4-1:0], ser_dti};  // MSB first
  else          ser_dat <= {ser_dti, ser_dat[32  -1:4]         };  // LSB first
end

// output mixer
always @ (*)
if (cyc_beg) begin
  case (ctl_iow)                                      // MSB first          LSB first
    2'd0 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? buf_dat[32-1+:1] : buf_dat[0+:1]};
    2'd1 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? buf_dat[32-1+:1] : buf_dat[0+:1]};
    2'd2 :  ser_dmo = {cfg_hlo, cfg_wpo,       cfg_dir ? buf_dat[32-2+:2] : buf_dat[0+:2]};
    2'd3 :  ser_dmo = {                        cfg_dir ? buf_dat[32-4+:4] : buf_dat[0+:4]};
  endcase
end else begin
  case (ctl_iow)                                      // MSB first                                 LSB first
    2'd0 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? ser_dat[32-1-{30'b0, ctl_btn[1:0]}+:1] : ser_dat[{30'b0, ctl_btn[1:0]}+:1]};
    2'd1 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? ser_dat[32-1-{30'b0, ctl_btn[1:0]}+:1] : ser_dat[{30'b0, ctl_btn[1:0]}+:1]};
    2'd2 :  ser_dmo = {cfg_hlo, cfg_wpo,       cfg_dir ? ser_dat[32-2-{30'b0, ctl_btn[1:0]}+:2] : ser_dat[{30'b0, ctl_btn[1:0]}+:2]};
    2'd3 :  ser_dmo = {                        cfg_dir ? ser_dat[32-8                      +:4] : ser_dat[0                    +:4]};
  endcase
end

// output enable mixer
always @ (*)
begin
  case (ctl_iow)
    2'd0 :  ser_dme = {cfg_hle, cfg_wpe, 1'b0, cyc_beg ? ctl_oen : ctl_oen & ~ctl_oec  };
    2'd1 :  ser_dme = {cfg_hle, cfg_wpe, 1'b0, cyc_beg ? ctl_oen : ctl_oen & ~ctl_oec  };
    2'd2 :  ser_dme = {cfg_hle, cfg_wpe,    {2{cyc_beg ? ctl_oen : ctl_oen & ~ctl_oec}}};
    2'd3 :  ser_dme = {                     {4{cyc_beg ? ctl_oen : ctl_oen & ~ctl_oec}}};
  endcase
end

////////////////////////////////////////////////////////////////////////////////
// slave select, clock, data (input, output, enable)                          //
////////////////////////////////////////////////////////////////////////////////

// spi slave select
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)         ioe_sso <= {SSW{1'b0}};
else begin
  if      (cyc_beg)  ioe_sso <= {SSW{ ctl_sse}} & cfg_sso [SSW-1:0];
  else if (cyc_end)  ioe_sso <= {SSW{~ctl_ssc}} & ioe_sso;
end

assign spi_ss_o = ioe_sso;
assign spi_ss_e = cfg_sse;


// spi clock output pin
assign spi_sclk_o = cfg_pol ^ ~(~cyc_run | clk_spi);
assign spi_sclk_e = cfg_coe;


// phase register input
always @ (negedge clk_spi)
if (~cfg_pha)  ioe_pri <= spi_sio_i;

// phase multiplexer input
// direct register input
always @ (posedge clk_spi)
ioe_dri <= cfg_pha ? ioe_pri : spi_sio_i;


// direct register output
always @ (posedge clk_spi)
ioe_dro <= ser_dmo;

// phase register output
always @ (negedge clk_spi)
if  (cfg_pha)  ioe_pro <= ioe_dro;

// phase multiplexer output
assign spi_sio_o = cfg_pha ? ioe_pro : ioe_dro;


// direct register output enable
always @ (posedge clk_spi, posedge rst_spi)
if  (rst_spi)            ioe_dre <= 4'b0000;
else
if  (cyc_beg | cyc_end)  ioe_dre <= ser_dme;

// phase register output enable
always @ (negedge clk_spi, posedge rst_spi)
if  (rst_spi)  ioe_pre <= 4'b0000;
else
if  (cfg_pha)  ioe_pre <= ioe_dre;

// phase multiplexer output enable
assign spi_sio_e = cfg_pha ? ioe_pre : ioe_dre;

endmodule
