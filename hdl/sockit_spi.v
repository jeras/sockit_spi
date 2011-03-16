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
wire           bus_wed;  // write data register
wire           bus_red;  // read  data register
wire           bus_wec;  // write control register
wire           bus_rec;  // read  status register

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

// TODO missing configuration registers

// XIP configuration TODO
reg     [31:0] xip_reg;  // XIP configuration
wire           xip_ena;  // XIP configuration

// clock domain crossing pipeline for control register
reg            pct_sts;  // CPU clock domain - pipeline status
wire           pct_wen;  // SPI clock domain - write enable
reg     [31:0] pct_wdt;  // SPI clock domain - write data

// clock domain crossing pipeline for SPI cycle
reg            pcy_sts;  // CPU clock domain - pipeline status

// control registers
reg            ctl_ssc;  // slave select clear
reg            ctl_sse;  // slave select enable
reg            ctl_ien;  // data input  enable
reg            ctl_orl;  // data output reload
reg            ctl_oel;  // data output enable last
reg            ctl_oec;  // data output enable clear
reg            ctl_oen;  // data output enable
reg      [1:0] ctl_iow;  // IO width (0-3wire, 1-SPI, 2-duo, 3-quad)
reg     [15:0] ctl_cnt;  // counter of transfer units (nibbles by default)

// clock domain crossing pipeline for output data
reg            pod_sts;  // CPU clock domain - pipeline status
wire           pod_wen;  // SPI clock domain - write enable

// clock domain crossing pipeline for input data
reg            pid_sts;  // CPU clock domain - pipeline status
wire           pid_ren;  // SPI clock domain - read enable

// clock domain crossing data buffer
reg     [31:0] pdt_dat;  // CPU clock domain - data register

// reload buffer
reg     [31:0] buf_dat;  // SPI clock domain - data register
reg            buf_oen;  // output enable (new data for output has been written)
reg            buf_ien;  //  input enable (new data from input has been read)

// fine grained counters
reg      [1:0] ctl_btc;  // counter of shifted bits
reg      [1:0] ctl_btn;  // counter of shifted bits next (+1)

// cycle timing registers
reg            cyc_beg;  // transfer begin pulse
reg            cyc_run;  // transfer run status
reg            cyc_nin;  // transfer nibble pulse next
reg            cyc_nib;  // transfer nibble pulse (registered version of cyc_nin)
reg            cyc_end;  // transfer end pulse
reg            cyc_rdy;  // transfer input ready pulse
// TODO
reg            cyc_odt;  // output data status
reg            cyc_idt;  //  input data status

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
  .fsm_rdt  (),  // read data
  .fsm_wrq  (bus_wrq),  // wait request
  // SPI master status
  .sts_cyc  (pcy_sts),  // cycle status
  // configuration
  .adr_off  (xip_reg[XAW-1:8])  // address offset
);

// data & controll register access multiplexer between two busses
assign bus_wen = xip_ena ? fsm_wen : reg_wen & reg_adr[1];  // write enable
assign bus_ren = xip_ena ? fsm_ren : reg_ren & reg_adr[1];  // read  enable
assign bus_adr = xip_ena ? fsm_adr : reg_adr[0];            // address
assign bus_wdt = xip_ena ? fsm_wdt : reg_wdt;               // write data

// register interface return signals
assign reg_rdt = ~reg_adr[1] ? (~reg_adr[0] ? reg_xip : reg_cfg)
                             : (~reg_adr[0] ? reg_sts : bus_rdt);  // read data
assign reg_wrq = ~reg_adr[1] ?                   1'b0 : bus_wrq;   // wait request

// wait request timing
assign bus_wrq = ~bus_adr ? (bus_wen & pct_sts)   // write to control register
                          : (bus_wen & pod_sts)   // write to  data register
                          | (bus_wen & pid_sts);  // read from data register

// control/status and data register write/read access transfers
assign bus_wec = bus_wen & ~bus_adr & ~bus_wrq;  // write control register
assign bus_rec = bus_ren & ~bus_adr & ~bus_wrq;  // read  control register
assign bus_wed = bus_wen &  bus_adr & ~bus_wrq;  // write data register
assign bus_red = bus_ren &  bus_adr & ~bus_wrq;  // read  data register

////////////////////////////////////////////////////////////////////////////////
// SPI status, interrupt request                                              //
////////////////////////////////////////////////////////////////////////////////

assign reg_sts = {28'h0000000, pid_sts, pod_sts, pcy_sts, pct_sts};

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
end else if (reg_wen & (reg_adr == 2'd0) & ~reg_wrq) begin
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
end else if (reg_wen & (reg_adr == 2'd1) & ~reg_wrq) begin
  xip_reg <= reg_wdt;
end

////////////////////////////////////////////////////////////////////////////////
// clock domain crossing pipeline (optional) for data register                //
////////////////////////////////////////////////////////////////////////////////

generate if (CDC) begin : pdt

  // clock domain crossing loop
  reg  [1:0] pod_cdl;  // CPU clock domain - loop
  reg  [1:0] pod_sdl;  // SPI clock domain - loop
  reg        pod_req;  // SPI clock domain - pipeline request

  // clock domain crossin loop
  reg  [1:0] pid_cdl;  // CPU clock domain - loop
  reg  [1:0] pid_sdl;  // SPI clock domain - loop
  reg        pid_req;  // SPI clock domain - pipeline request

  // status of control register pipeline
  always @ (posedge clk_cpu, posedge rst_cpu)
  if (rst_cpu)  pod_sts <= 1'b0;
  else          pod_sts <= ^pod_cdl | bus_wed;

  // clock domain CPU, control register write toggle
  always @ (posedge clk_cpu, posedge rst_cpu)
  if (rst_cpu)  pod_cdl <= 2'b00;
  else          pod_cdl <= {pod_sdl[0], pod_cdl [0] ^  bus_wed};

  // SPI clock domain
  always @ (posedge clk_spi, posedge rst_spi)
  if (rst_spi)  pod_sdl <= 2'b00;
  else          pod_sdl <= {pod_cdl[0], cyc_odt ? pod_sdl[0] : pod_sdl[1]};

  // request control register pipeline
  always @ (posedge clk_spi, posedge rst_spi)
  if (rst_spi)  pod_req <= 1'b0;
  else          pod_req <= ^pod_sdl;

  // data registers write enable // TODO
  assign        pod_wen = pod_req & ~cyc_odt;

  // data register
  always @ (posedge clk_cpu)
  if (bus_wed)  pdt_dat <= bus_wdt;
  else
  if (pid_ren)  pdt_dat <= buf_dat;

  //  registers write data
  assign        bus_rdt = pdt_dat;

  // status of control register pipeline
  always @ (posedge clk_cpu, posedge rst_cpu)
  if (rst_cpu)  pid_sts <= 1'b0;
  else          pid_sts <= ^pid_cdl | bus_red;

  // clock domain CPU, control register write toggle
  always @ (posedge clk_cpu, posedge rst_cpu)
  if (rst_cpu)  pid_cdl <= 2'b00;
  else          pid_cdl <= {pid_sdl[0], pid_cdl [0] ^  bus_red};

  // SPI clock domain
  always @ (posedge clk_spi, posedge rst_spi)
  if (rst_spi)  pid_sdl <= 2'b00;
  else          pid_sdl <= {pid_cdl[0], cyc_idt ? pid_sdl[0] : pid_sdl[1]};

  // request control register pipeline
  always @ (posedge clk_spi, posedge rst_spi)
  if (rst_spi)  pid_req <= 1'b0;
  else          pid_req <= ^pid_sdl;

  // data registers read enable // TODO
  assign        pid_ren = pid_req & ~cyc_idt;

end else begin : pdt

  // status of output data pipeline
  always @ (*)  pod_sts = cyc_odt;

  // data registers write enable
  assign        pod_wen = bus_wed;

  // write data
  always @ (*)  pdt_dat = bus_wdt;

  // read data
  assign        bus_rdt = buf_dat;

  // status of  input data pipeline
  always @ (*)  pid_sts = cyc_idt;

  // data registers read enable
  assign        pid_ren = bus_red;

  // bus read data
  assign        bus_rdt = buf_dat;

end endgenerate

// buffer for swapping write/read data with shift register
always @ (posedge clk_spi)
if      (pod_wen)  buf_dat <= pdt_dat;                                 // CPU load
else if (cyc_rdy)  buf_dat <= cfg_dir ? {ser_dat[32-4-1:0], ser_dmi}   // MSB first
                                      : {ser_dmi, ser_dat[32  -1:4]};  // LSB first

// output enable (new data for output has been written) 
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)         buf_oen <= 1'b0;
else begin
  if      (pod_wen)  buf_oen <= 1'b0;
  else if (cyc_beg)  buf_oen <= ~ctl_orl;
end

//  input enable (new data from input has been read)
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)         buf_ien <= 1'b1;
else begin
  if      (pid_ren)  buf_ien <= 1'b0;
  else if (cyc_rdy)  buf_ien <= ~ctl_ien;
end

////////////////////////////////////////////////////////////////////////////////
// clock domain crossing pipeline (optional) for control register             //
////////////////////////////////////////////////////////////////////////////////

generate if (CDC) begin : pct

  // clock domain crossin loop
  reg  [1:0] pct_cdl;  // CPU clock domain - loop
  reg  [1:0] pct_sdl;  // SPI clock domain - loop
  reg        pct_req;  // SPI clock domain - pipeline request

  // control registers write data
  always @ (posedge clk_cpu)
  if (bus_wec)  pct_wdt <= bus_wdt;

  // status of control register pipeline
  always @ (posedge clk_cpu, posedge rst_cpu)
  if (rst_cpu)  pct_sts <= 1'b0;
  else          pct_sts <= ^pct_cdl | bus_wec;

  // clock domain CPU, control register write toggle
  always @ (posedge clk_cpu, posedge rst_cpu)
  if (rst_cpu)  pct_cdl <= 2'b00;
  else          pct_cdl <= {pct_sdl[0], pct_cdl [0] ^  bus_wec};

  // SPI clock domain
  always @ (posedge clk_spi, posedge rst_spi)
  if (rst_spi)  pct_sdl <= 2'b00;
  else          pct_sdl <= {pct_cdl[0], cyc_odt ? pct_sdl[0] : pct_sdl[1]};

  // request control register pipeline
  always @ (posedge clk_spi, posedge rst_spi)
  if (rst_spi)  pct_req <= 1'b0;
  else          pct_req <= ^pct_sdl;

  // control registers write enable // TODO
  assign        pct_wen = pct_req & ~cyc_odt;

end else begin : pct

  // control registers write data
  always @ (*)  pct_wdt = bus_wdt;

  // status of control register pipeline
  always @ (*)  pct_sts = cyc_odt;

  // control registers write enable
  assign        pct_wen = bus_wec;

end endgenerate

////////////////////////////////////////////////////////////////////////////////
// clock domain crossing pipeline (optional) for SPI cycle status             //
////////////////////////////////////////////////////////////////////////////////

generate if (CDC) begin : pcy

  // clock domain crossin loop
  reg  [1:0] pcy_cdl;  // CPU clock domain - loop
  reg  [1:0] pcy_sdl;  // SPI clock domain - loop
  reg        pcy_req;  // SPI clock domain - pipeline request

  // status of SPI cycle
  always @(*)  pcy_sts = cyc_odt;

end else begin : pcy

  // status of SPI cycle
  always @(*)  pcy_sts = cyc_odt;

end endgenerate

////////////////////////////////////////////////////////////////////////////////
// control registers                                                          //
////////////////////////////////////////////////////////////////////////////////

// transfer length counter
always @(posedge clk_cpu, posedge rst_cpu)
if (rst_cpu) begin
  ctl_ssc <=  1'b0;
  ctl_sse <=  1'b0;
  ctl_ien <=  1'b0;
  ctl_orl <=  1'b0;
  ctl_oel <=  1'b0;
  ctl_oec <=  1'b0;
  ctl_oen <=  1'b0;
  ctl_iow <=  2'd0;
  ctl_cnt <= 16'd0;
end else begin
  // write from the CPU bus has priority
  if (pct_wen) begin
    ctl_ien <= pct_wdt[24   ];
    ctl_oec <= pct_wdt[23   ];
    ctl_oel <= pct_wdt[22   ];
    ctl_orl <= pct_wdt[21   ];
    ctl_oen <= pct_wdt[20   ];
    ctl_ssc <= pct_wdt[19   ];
    ctl_sse <= pct_wdt[18   ];
    ctl_iow <= pct_wdt[17:16];
    ctl_cnt <= pct_wdt[15: 0];
  // decrement at the end of each transfer unit (nibble by default)
  end else if (cyc_nib) begin
    ctl_cnt <= ctl_cnt - 16'd1;
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
else          cyc_beg <= pct_wen;

// spi transfer run status
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_run <= 1'b0;
else      cyc_run <= cyc_beg | cyc_run & ~cyc_end;

// spi transfer end pulse
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_end <= 1'b0;
else          cyc_end <= cyc_nin & (ctl_cnt == ((ctl_iow == 2'd3) ? 16'd1 : 16'd0));

// input ready pulse
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_rdy <= 1'b0;
else          cyc_rdy <= cyc_end;

// status registers
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi) begin
  cyc_odt <= 1'b0;
  cyc_idt <= 1'b0;
end else begin
  if (pct_wen) begin
//    cyc_odt <= pct_wdt[16];
//    cyc_idt <= pct_wdt[18];
    cyc_odt <= 1'b1;
    cyc_idt <= 1'b1;
  end else begin
    if ((ctl_cnt == 16'd0) & cyc_nin) cyc_odt <= 1'b0;
    if (cyc_end)                      cyc_idt <= 1'b0;
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
