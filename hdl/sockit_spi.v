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
wire           pct_sts;  // CPU clock domain - pipeline status
wire   [31: 0] ctl_dat;  // SPI clock domain - write data
reg    [24:16] ctl_reg;  // SPI clock domain - register

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

// clock domain crossing pipeline for SPI cycle
reg            pcy_sts;  // CPU clock domain - pipeline status

// clock domain crossing pipeline for output data
wire           pod_sts;  // CPU clock domain - pipeline status

// clock domain crossing pipeline for input data
wire           pid_sts;  // CPU clock domain - pipeline status

// reload buffer
wire    [31:0] buf_wdt;  // SPI clock domain - write data
wire    [31:0] buf_rdt;  // SPI clock domain - read  data

// fine grained counters
reg      [1:0] ctl_btc;  // counter of shifted bits
reg      [1:0] ctl_btn;  // counter of shifted bits next (+1)

// cycle timing registers
wire           cyc_beg;  // transfer begin pulse
reg            cyc_run;  // transfer run status
reg            cyc_nen;  // transfer nibble enable next   pulse
reg            cyc_neo;  // transfer nibble enable output pulse (registered version of cyc_nen)
reg            cyc_nei;  // transfer nibble enable  input pulse (registered version of cyc_neo)
reg            cyc_end;  // transfer end pulse
reg            cyc_rdy;  // transfer input ready pulse

// serialization
reg      [3:0] ser_dmi;  // data mixer input register
reg      [2:0] ser_dsi;  // data shift input register
reg      [3:0] ser_dpi;  // data shift phase synchronization
reg     [31:0] ser_dri;  // data shift register input
reg     [31:0] ser_dro;  // data shift register output
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
assign bus_wrq = ~bus_adr ? (bus_wen & ~pct_sts)   // write to control register
                          : (bus_wen & ~pod_sts)   // write to  data register
                          | (bus_ren & ~pid_sts);  // read from data register

// control/status and data register write/read access transfers
assign bus_wec = bus_wen & ~bus_adr & ~bus_wrq;  // write control register
assign bus_rec = bus_ren & ~bus_adr & ~bus_wrq;  // read  control register
assign bus_wed = bus_wen &  bus_adr & ~bus_wrq;  // write data register
assign bus_red = bus_ren &  bus_adr & ~bus_wrq;  // read  data register

////////////////////////////////////////////////////////////////////////////////
// SPI status, interrupt request                                              //
////////////////////////////////////////////////////////////////////////////////

assign reg_sts = {pid_sts, pod_sts, pcy_sts, pct_sts, 28'h0000000};

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

  // write data
  sockit_spi_cdc #(
    .CW       ( 1),
    .DW       (32)
  ) cdc_pod (
    // input port
    .cdi_clk  (clk_cpu),
    .cdi_rst  (rst_cpu),
    .cdi_dat  (bus_wdt),
    .cdi_pli  (bus_wed),
    .cdi_plo  (pod_sts),
    // output port
    .cdo_clk  (clk_spi),
    .cdo_rst  (rst_spi),
    .cdo_pli  (cyc_beg),
    .cdo_plo  (),  // TODO
    .cdo_dat  (buf_wdt)
  );

  // read data
  sockit_spi_cdc #(
    .CW       ( 1),
    .DW       (32)
  ) cdc_pid (
    // input port
    .cdi_clk  (clk_spi),
    .cdi_rst  (rst_spi),
    .cdi_dat  (buf_rdt),
    .cdi_pli  (cyc_rdy),
    .cdi_plo  (),  // TODO
    // output port
    .cdo_clk  (clk_cpu),
    .cdo_rst  (rst_cpu),
    .cdo_pli  (bus_red),
    .cdo_plo  (pid_sts),
    .cdo_dat  (bus_rdt)
  );

end else begin : pdt

  reg [31:0] buf_dat;

  // write data
  assign pod_sts = cyc_run;
  assign buf_wdt = bus_wdt;

  // read data
  assign pid_sts = 1'bx;     // TODO
  assign bus_rdt = buf_dat;

end endgenerate

////////////////////////////////////////////////////////////////////////////////
// clock domain crossing pipeline (optional) for control register             //
////////////////////////////////////////////////////////////////////////////////

generate if (CDC) begin : pct

  wire cdo_plo;
  wire cdo_pli;

  sockit_spi_cdc #(
    .CW       ( 1),
    .DW       (32)
  ) cdc_ctl (
    // input port
    .cdi_clk  (clk_cpu),
    .cdi_rst  (rst_cpu),
    .cdi_dat  (bus_wdt),
    .cdi_pli  (bus_wec),
    .cdi_plo  (pct_sts),
    // output port B
    .cdo_clk  (clk_spi),
    .cdo_rst  (rst_spi),
    .cdo_pli  (cdo_pli),
    .cdo_plo  (cdo_plo),
    .cdo_dat  (ctl_dat)
  );

  assign cdo_pli = cyc_end | ~cyc_run;
  assign cyc_beg = cdo_plo & cdo_pli;

end else begin : pct

  assign pct_sts = 1'bx;
  assign ctl_dat = bus_wdt;
  assign cyc_beg = bus_wec;

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
  always @(*)  pcy_sts = cyc_run;

end else begin : pcy

  // status of SPI cycle
  always @(*)  pcy_sts = cyc_run;

end endgenerate

////////////////////////////////////////////////////////////////////////////////
// control registers                                                          //
////////////////////////////////////////////////////////////////////////////////

reg [24:16] pct_reg;

// transfer length counter
always @(posedge clk_cpu, posedge rst_cpu)
if (rst_cpu) begin
  ctl_reg <= 12'h000;
  ctl_cnt <= 16'h0000;
end else begin
  // write from the CPU bus has priority
  if (cyc_beg) begin
    ctl_reg <= ctl_dat[24:16];
    ctl_cnt <= ctl_dat[15: 0];
  // decrement at the end of each transfer unit (nibble by default)
  end else if (~|ctl_btn & cyc_run) begin
    ctl_cnt <= ctl_cnt - 16'd1;
  end
end

always @ (*) ctl_ien =                            ctl_reg[24   ];
always @ (*) ctl_oec = cyc_beg ? ctl_dat[23   ] : ctl_reg[23   ];
always @ (*) ctl_oel = cyc_beg ? ctl_dat[22   ] : ctl_reg[22   ];
always @ (*) ctl_orl = cyc_beg ? ctl_dat[21   ] : ctl_reg[21   ];
always @ (*) ctl_oen = cyc_beg ? ctl_dat[20   ] : ctl_reg[20   ];
always @ (*) ctl_ssc = cyc_beg ? ctl_dat[19   ] : ctl_reg[19   ];
always @ (*) ctl_sse = cyc_beg ? ctl_dat[18   ] : ctl_reg[18   ];
always @ (*) ctl_iow = cyc_beg ? ctl_dat[17:16] : ctl_reg[17:16];

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

// nibbleenable next pulse
always @ (*)
begin
  case (ctl_iow)
    2'd0 :  cyc_nen = &ctl_btn[1:0];  // 3-wire
    2'd1 :  cyc_nen = &ctl_btn[1:0];  // spi
    2'd2 :  cyc_nen = &ctl_btn[1  ];  // dual
    2'd3 :  cyc_nen =          1'b1;  // quad
  endcase
end

// nibble enable output pulse
always @ (*)  cyc_neo  = cyc_nen & (cyc_run | (ctl_iow == 2'd3) & cyc_beg) & ~cyc_end;

// nibble enable input pulse
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_nei <= 1'b0;
else          cyc_nei <= ~|ctl_btn & cyc_run & ctl_ien;

// spi transfer run status
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_run <= 1'b0;
else          cyc_run <= cyc_beg | cyc_run & ~cyc_end;

// spi transfer end pulse
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_end <= 1'b0;
else          cyc_end <= cyc_nen & (ctl_cnt == ((ctl_iow == 2'd3) ? 16'd1 : 16'd0));

// input ready pulse
always @ (posedge clk_spi, posedge rst_spi)
if (rst_spi)  cyc_rdy <= 1'b0;
else          cyc_rdy <= cyc_end & ctl_ien;

////////////////////////////////////////////////////////////////////////////////
// serialization input                                                        //
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

// shift data register  input (nibble sized shifts)
always @ (posedge clk_spi)
if (cyc_nei) ser_dri <= buf_rdt;

assign buf_rdt = cfg_dir ? {         ser_dri[32-4-1:0], ser_dmi}   // MSB first
                         : {ser_dmi, ser_dri[32  -1:4]         };  // LSB first

////////////////////////////////////////////////////////////////////////////////
// serialization output                                                       //
////////////////////////////////////////////////////////////////////////////////

// shift data register output (nibble sized shifts)
always @ (posedge clk_spi)
if   (cyc_beg)  ser_dro <=           buf_wdt                    ;  // par. load
else if (cyc_neo) begin
  if (cfg_dir)  ser_dro <= {         ser_dro[32-4-1:0], 4'bxxxx};  // MSB first
  else          ser_dro <= {4'bxxxx, ser_dro[32  -1:4]         };  // LSB first
end

// output mixer
always @ (*)
if (cyc_beg) begin
  case (ctl_iow)                                      // MSB first          LSB first
    2'd0 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? buf_wdt[32-1+:1] : buf_wdt[0+:1]};
    2'd1 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? buf_wdt[32-1+:1] : buf_wdt[0+:1]};
    2'd2 :  ser_dmo = {cfg_hlo, cfg_wpo,       cfg_dir ? buf_wdt[32-2+:2] : buf_wdt[0+:2]};
    2'd3 :  ser_dmo = {                        cfg_dir ? buf_wdt[32-4+:4] : buf_wdt[0+:4]};
  endcase
end else begin
  case (ctl_iow)                                      // MSB first                                 LSB first
    2'd0 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? ser_dro[32-1-{30'b0, ctl_btn[1:0]}+:1] : ser_dro[{30'b0, ctl_btn[1:0]}+:1]};
    2'd1 :  ser_dmo = {cfg_hlo, cfg_wpo, 1'bx, cfg_dir ? ser_dro[32-1-{30'b0, ctl_btn[1:0]}+:1] : ser_dro[{30'b0, ctl_btn[1:0]}+:1]};
    2'd2 :  ser_dmo = {cfg_hlo, cfg_wpo,       cfg_dir ? ser_dro[32-2-{30'b0, ctl_btn[1:0]}+:2] : ser_dro[{30'b0, ctl_btn[1:0]}+:2]};
    2'd3 :  ser_dmo = {                        cfg_dir ? ser_dro[32-8                      +:4] : ser_dro[0                    +:4]};
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
