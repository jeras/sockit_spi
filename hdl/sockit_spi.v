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
// this file contains:                                                        //
// - the system bus interface                                                 //
// - static configuration registers                                           //
// - SPI state machine and serialization logic                                //
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
  parameter SDW     =            8,  // serial data register width
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
  input  wire           reg_ren,     // read enable
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
wire           pct_sts;  // pipeline status

// clock domain crossing pipeline for output data
wire           pod_sts;  // CPU clock domain - pipeline status

// clock domain crossing pipeline for input data
wire           pid_sts;  // CPU clock domain - pipeline status

localparam BOW = 4*SDW + SSW + 11;
localparam BIW = 4*SDW + 1;

wire           bfo_wer;
wire           bfo_weg;
wire [BOW-1:0] bfo_wdt;
wire [BOW-1:0] bfo_rdt;
wire           bfo_rer;
wire           bfo_reg;

wire           bfi_rer;
wire           bfi_reg;
wire [BIW-1:0] bfi_rdt;
wire [BIW-1:0] bfi_wdt;
wire           bfi_wer;
wire           bfi_weg;

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
// data repackaging                                                           //
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// spi clock domain signals                                                   //
////////////////////////////////////////////////////////////////////////////////

reg      [2:0] spi_cnt;  // clock counter
reg            spi_cke;  // clock enable

reg            spi_sie;
reg      [3:0] spi_soe;
reg            spi_sce;
reg            spi_sco;
reg  [SSW-1:0] spi_sse;
reg  [SSW-1:0] spi_sso;

reg  [SDW-1:0] spi_sdo [0:3];
wire [SDW-1:0] spi_dto_3;
wire [SDW-1:0] spi_dto_2;
wire [SDW-1:0] spi_dto_1;
wire [SDW-1:0] spi_dto_0;

reg  [SDW-1:0] spi_sdi [0:3];
wire [SDW-1:0] spi_dti_3;
wire [SDW-1:0] spi_dti_2;
wire [SDW-1:0] spi_dti_1;
wire [SDW-1:0] spi_dti_0;

wire           spi_new;

////////////////////////////////////////////////////////////////////////////////
// clock domain crossing pipeline (optional) for data register                //
////////////////////////////////////////////////////////////////////////////////

generate if (CDC) begin : cdc

  // data output
  sockit_spi_cdc #(
    .CW       ( 1),
    .DW       (BOW)
  ) cdc_bfo (
    // input port
    .cdi_clk  (clk_cpu),
    .cdi_rst  (rst_cpu),
    .cdi_dat  (bus_wdt),
    .cdi_pli  (bus_wed),
    .cdi_plo  (pod_sts),
    // output port
    .cdo_clk  (clk_spi),
    .cdo_rst  (rst_spi),
    .cdo_pli  (bfo_reg),
    .cdo_plo  (bfo_rer),
    .cdo_dat  (bfo_rdt)
  );

  // data input
  sockit_spi_cdc #(
    .CW       ( 1),
    .DW       (BIW)
  ) cdc_bfi (
    // input port
    .cdi_clk  (clk_spi),
    .cdi_rst  (rst_spi),
    .cdi_dat  (bfi_wdt),
    .cdi_pli  (bfi_wer),
    .cdi_plo  (bfi_weg),
    // output port
    .cdo_clk  (clk_cpu),
    .cdo_rst  (rst_cpu),
    .cdo_pli  (bus_red),
    .cdo_plo  (pid_sts),
    .cdo_dat  (bus_rdt)
  );

end else begin : syn

  reg [31:0] buf_dat;

  // write data
  assign pod_sts = cyc_run;
  assign buf_wdt = bus_wdt;

  // read data
  assign pid_sts = 1'bx;     // TODO
  assign bus_rdt = buf_dat;

end endgenerate

// flow control for data output
assign bfo_reg = ~|spi_cnt;
assign bfo_ren = bfo_rer & bfo_reg;

// flow control for data input
assign bfi_weg = spi_sie & spi_cke & ~|spi_cnt;
assign bfi_wen = bfi_wer & bfi_weg;

////////////////////////////////////////////////////////////////////////////////
// spi cycle timing                                                           //
////////////////////////////////////////////////////////////////////////////////

// transfer length counter
always @(posedge clk_spi, posedge rst_spi)
if (rst_spi) begin
  spi_cke <= 1'b0;
  spi_cnt <= 3'd0;
end else begin
  if (bfo_ren) begin
    spi_cke <= bfo_rdt [4*SDW-1+0+:1];
    spi_cnt <= bfo_rdt [4*SDW-1+1+:3];
  end else begin
    if (bfo_reg)  spi_cke <= 1'b0;
    if (spi_cke)  spi_cnt <= spi_cnt - 3'd1;
  end
end

// IO control registers
always @(posedge clk_spi, posedge rst_spi)
if (rst_spi) begin
  spi_sie <=      1'b0;
  spi_soe <=      4'h0;
  spi_sce <=      1'b0;
  spi_sco <=      1'b0;
  spi_sse <= {SSW{1'b0}};
  spi_sso <= {SSW{1'b0}};
end else if (bfo_ren) begin
  spi_sie <=      bfo_rdt [4*SDW-1+  4 +:1];
  spi_soe <=      bfo_rdt [4*SDW-1+  5 +:4];
  spi_sce <=      bfo_rdt [4*SDW-1+  9 +:1];
  spi_sco <=      bfo_rdt [4*SDW-1+ 10 +:1];
  spi_sse <= {SSW{bfo_rdt [4*SDW-1+ 11 +:1]}};
  spi_sso <=      bfo_rdt [4*SDW-1+ 12 +:SSW];
end

assign spi_dto_3 = bfo_rdt [SDW*3+:SDW];
assign spi_dto_2 = bfo_rdt [SDW*2+:SDW];
assign spi_dto_1 = bfo_rdt [SDW*1+:SDW];
assign spi_dto_0 = bfo_rdt [SDW*0+:SDW];

assign bfi_dat = {spi_new,
                  spi_dti_3,
                  spi_dti_2,
                  spi_dti_1,
                  spi_dti_0};

////////////////////////////////////////////////////////////////////////////////
// slave select, clock, data (input, output, enable)                          //
////////////////////////////////////////////////////////////////////////////////

// serial clock input
assign spi_cli =  spi_sclk_i ^ (cfg_pol ^ cfg_pha);  // clock for input registers
assign spi_clo = ~spi_sclk_i ^ (cfg_pol ^ cfg_pha);  // clock for output registers

// serial clock output
assign spi_sclk_o = cfg_pol ^ ~(~spi_cke | clk_spi);
assign spi_sclk_e = cfg_coe;


// slave select input
assign spi_rsi = spi_ss_i;  // reset for output registers

// slave select output, output enable
assign spi_ss_o = spi_sso;
assign spi_ss_e = spi_sse;


// data input
always @ (posedge spi_cli)
begin
  spi_sdi [3] <= spi_dti_3;
  spi_sdi [2] <= spi_dti_2;
  spi_sdi [1] <= spi_dti_1;
  spi_sdi [0] <= spi_dti_0;
end

assign spi_dti_3 = {spi_sdi [3], spi_ss_i [3]};
assign spi_dti_2 = {spi_sdi [2], spi_ss_i [2]};
assign spi_dti_1 = {spi_sdi [1], spi_ss_i [1]};
assign spi_dti_0 = {spi_sdi [0], spi_ss_i [0]};

// data output
always @ (posedge spi_clo)
if (bfo_ren) begin
  spi_sdo [3] <=  spi_dto_3;
  spi_sdo [2] <=  spi_dto_2;
  spi_sdo [1] <=  spi_dto_1;
  spi_sdo [0] <=  spi_dto_0;
end else begin
  spi_sdo [3] <= {spi_sdo [3] [SDW-1:0], 1'bx};
  spi_sdo [2] <= {spi_sdo [2] [SDW-1:0], 1'bx};
  spi_sdo [1] <= {spi_sdo [1] [SDW-1:0], 1'bx};
  spi_sdo [0] <= {spi_sdo [0] [SDW-1:0], 1'bx};
end

assign spi_sio_o [3] = spi_sdo [3] [SDW-1];
assign spi_sio_o [2] = spi_sdo [2] [SDW-1];
assign spi_sio_o [1] = spi_sdo [1] [SDW-1];
assign spi_sio_o [0] = spi_sdo [0] [SDW-1];

// data output enable
assign spi_sio_e = spi_soe;

endmodule
