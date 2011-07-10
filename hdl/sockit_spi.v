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
//                                                                            //
// Block diagram (data stages, block connections, internal protocols):        //
//                                                                            //
//                                                                            //
//  SYSTEM       BUS     INTERNAL  REPACKAGING   CLOCK     SERIALIZER         //
//  BUSES    INTERFACES   ARBITER                DOMAIN        DE-            //
//                                               CROSSING  SERIALIZER         //
//             -------     -----                                              //
//   reg_* --> | REG | <=> |   |                                              //
//             -------     | a |     -------     -------     -----            //
//                |        | r | --> | RPO | --> | CDC | --> |   |            //
//                v        | b |     -------     -------     | S |            //
//             -------     | i |                             | E | <=> SPI_*  //
//   dma_* <-- | DMA | <=> | t |     -------     -------     | R |            //
//             -------     | e | <-- | RPI | <-- | CDC | <-- |   |            //
//             -------     | r |     -------     -------     -----            //
//   xip_* --> | XIP | <=> |   |                                              //
//             -------     -----                                              //
//                                                                            //
//           DMA CONTROL  COMMAND                 QUEUE                       //
//            PROTOCOL    PROTOCOL               PROTOCOL                     //
//                                                                            //
//                                                                            //
// The above diagram shows the main building blocks of the sockit_spi module. //
// Most blocks are contained in separate modules:                             //
// - sockit_spi_reg  -  configuration, control, status registers              //
// - sockit_spi_dma  -  DMA (Direct Memory Access) interface                  //
// - sockit_spi_xip  -  XIP (eXecute In Place) interface                      //
// - sockit_spi_rpo  -  repackaging output (command into queue protocol)      //
// - sockit_spi_rpi  -  repackaging input  (queue into command protocol)      //
// - sockit_spi_cdc  -  asynchronous clock domain crossing FIFO               //
// - sockit_spi_ser  -  data serializer/de-serializer, clave selects, clocks  //
//                                                                            //
// Internal protocols are used to transfer data, commands and status between  //
// building blocks.                                                           //
// - dma task        -  DMA task requests from a system CPU                   //
// - command         -  32bit data packets + control bits                     //
// - queue           -   8bit data packets + control bits (sized for serial.) //
// The DMA related protocol is described inside sockit_spi_dma.v, command and //
// queue protocols are described inside sockit_spi_rpo.v and sockit_spi_rpi.v //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi #(
  // configuration (register reset values and masks)
  parameter CFG_RST = 32'h00000000,  // configuration register reset value
  parameter CFG_MSK = 32'hffffffff,  // configuration register implementation mask
  parameter ADR_ROF = 32'h00000000,  // address write offset
  parameter ADR_WOF = 32'h00000000,  // address read  offset
  //
  parameter NOP     = 32'h00000000,  // no operation instruction for the given CPU
  parameter XAW     =           24,  // XIP address width
  parameter DAW     =           32,  // DMA address width
  parameter SSW     =            8,  // slave select width
  parameter SDW     =            8,  // serial data register width
  parameter SDL     =  $clog2(SDW),  // serial data register width logarithm
  parameter CDC     =         1'b0   // implement clock domain crossing
)(
  // system signals (used by the CPU interface)
  input  wire           clk_cpu,     // clock for CPU interface
  input  wire           rst_cpu,     // reset for CPU interface
  input  wire           clk_spi,     // clock for SPI IO
  input  wire           rst_spi,     // reset for SPI IO
  // registers interface bus (slave)
  input  wire           reg_wen,     // write enable
  input  wire           reg_ren,     // read enable
  input  wire     [2:0] reg_adr,     // address
  input  wire    [31:0] reg_wdt,     // write data
  output wire    [31:0] reg_rdt,     // read data
  output wire           reg_wrq,     // wait request
  output wire           reg_err,     // error response
  output wire           reg_irq,     // interrupt request
  // XIP interface bus (slave)
  input  wire           xip_wen,     // write enable
  input  wire           xip_ren,     // read enable
  input  wire [XAW-1:0] xip_adr,     // address
  input  wire     [3:0] xip_ben,     // byte enable
  input  wire    [31:0] xip_wdt,     // write data
  output wire    [31:0] xip_rdt,     // read data
  output wire           xip_wrq,     // wait request
  output wire           xip_err,     // error response
  // DMA interface bus (master)
  output wire           dma_wen,     // write enable
  output wire           dma_ren,     // read enable
  output wire [DAW-1:0] dma_adr,     // address
  output wire     [3:0] dma_ben,     // byte enable
  output wire    [31:0] dma_wdt,     // write data
  input  wire    [31:0] dma_rdt,     // read data
  input  wire           dma_wrq,     // wait request
  input  wire           dma_err,     // error response

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
  input  wire [SSW-1:0] spi_ss_i,    // input  (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_o,    // output (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_e     // output enable
);

////////////////////////////////////////////////////////////////////////////////
// local parameters and signals                                               //
////////////////////////////////////////////////////////////////////////////////

// command parameters
localparam CCO =          5+6;  // control output width
localparam CCI =            4;  // control  input width
localparam CDW =           32;  // data width

// queue parameters
localparam QCO =        SDL+7;  // control output width
localparam QCI =            4;  // control  input width
localparam QDW =        4*SDW;  // data width

// SPI/XIP/DMA configuration
wire           cfg_pol;  // clock polarity
wire           cfg_pha;  // clock phase
wire           cfg_coe;  // clock output enable
wire           cfg_sse;  // slave select output enable
wire           cfg_m_s;  // mode (0 - slave, 1 - master)
wire           cfg_dir;  // shift direction (0 - lsb first, 1 - msb first)
wire     [7:0] cfg_xip;  // XIP configuration
wire     [7:0] cfg_dma;  // DMA configuration

// address offsets
wire    [31:0] adr_rof;  // address read  offset
wire    [31:0] adr_wof;  // address write offset

// command output
wire           reg_cmo_req, xip_cmo_req, dma_cmo_req,  cmo_req;  // request
wire [CCO-1:0] reg_cmo_ctl, xip_cmo_ctl, dma_cmo_ctl,  cmo_ctl;  // control
wire [CDW-1:0] reg_cmo_dat, xip_cmo_dat, dma_cmo_dat,  cmo_dat;  // data
wire           reg_cmo_grt, xip_cmo_grt, dma_cmo_grt,  cmo_grt;  // grant
// command input
wire           reg_cmi_req, xip_cmi_req, dma_cmi_req,  cmi_req;  // request
wire [CCI-1:0] reg_cmi_ctl, xip_cmi_ctl, dma_cmi_ctl,  cmi_ctl;  // control
wire [CDW-1:0] reg_cmi_dat, xip_cmi_dat, dma_cmi_dat,  cmi_dat;  // data
wire           reg_cmi_grt, xip_cmi_grt, dma_cmi_grt,  cmi_grt;  // grant

// queue output
wire           qow_req, qor_req;  // request
wire [QCO-1:0] qow_ctl, qor_ctl;  // control
wire [QDW-1:0] qow_dat, qor_dat;  // data
wire           qow_grt, qor_grt;  // grant
// queue input
wire           qir_req, qiw_req;  // request
wire [QCI-1:0] qir_ctl, qiw_ctl;  // control
wire [QDW-1:0] qir_dat, qiw_dat;  // data
wire           qir_grt, qiw_grt;  // grant

// DMA task interface
wire           tsk_req;  // request
wire    [21:0] tsk_ctl;  // control
wire     [1:0] tsk_sts;  // status
wire           tsk_grt;  // grant

// SPI clocks
wire           spi_cko;  // output registers
wire           spi_cki;  // input  registers

////////////////////////////////////////////////////////////////////////////////
// REG instance                                                               //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_reg #(
  // configuration
  .CFG_RST  (CFG_RST),
  .CFG_MSK  (CFG_MSK),
  .ADR_ROF  (ADR_ROF),
  .ADR_WOF  (ADR_WOF),
  // port widths
  .XAW      (XAW    )
) rgs (
  // system signals
  .clk      (clk_cpu),  // clock
  .rst      (rst_cpu),  // reset
  // register interface
  .reg_wen  (reg_wen),
  .reg_ren  (reg_ren),
  .reg_adr  (reg_adr),
  .reg_wdt  (reg_wdt),
  .reg_rdt  (reg_rdt),
  .reg_wrq  (reg_wrq),
  .reg_err  (reg_err),
  .reg_irq  (reg_irq),
  // SPI/XIP/DMA configuration
  .cfg_pol  (cfg_pol),
  .cfg_pha  (cfg_pha),
  .cfg_coe  (cfg_coe),
  .cfg_sse  (cfg_sse),
  .cfg_m_s  (cfg_m_s),
  .cfg_dir  (cfg_dir),
  .cfg_xip  (cfg_xip),
  .cfg_dma  (cfg_dma),
  // address offsets
  .adr_rof  (adr_rof),
  .adr_wof  (adr_wof),
  // command output
  .cmo_req  (reg_cmo_req),
  .cmo_ctl  (reg_cmo_ctl),
  .cmo_dat  (reg_cmo_dat),
  .cmo_grt  (reg_cmo_grt),
  // command input
  .cmi_req  (reg_cmi_req),
  .cmi_ctl  (reg_cmi_ctl),
  .cmi_dat  (reg_cmi_dat),
  .cmi_grt  (reg_cmi_grt),
  // DMA task interface
  .tsk_req  (tsk_req),
  .tsk_ctl  (tsk_ctl),
  .tsk_sts  (tsk_sts),
  .tsk_grt  (tsk_grt)
);

////////////////////////////////////////////////////////////////////////////////
// XIP instance                                                               //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_xip #(
  // configuration
  .NOP      (NOP    ),
  // port widths
  .XAW      (XAW    )
) xip (
  // system signals
  .clk      (clk_cpu),
  .rst      (rst_cpu),
  // input bus (XIP requests)
  .xip_wen  (xip_wen),
  .xip_ren  (xip_ren),
  .xip_adr  (xip_adr),
  .xip_ben  (xip_ben),
  .xip_wdt  (xip_wdt),
  .xip_rdt  (xip_rdt),
  .xip_wrq  (xip_wrq),
  .xip_err  (xip_err),
  // configuration
  .cfg_xip  (cfg_xip),
  .adr_rof  (adr_rof),
  .adr_wof  (adr_wof),
  // command output
  .cmo_req  (xip_cmo_req),
  .cmo_ctl  (xip_cmo_ctl),
  .cmo_dat  (xip_cmo_dat),
  .cmo_grt  (xip_cmo_grt),
  // command input
  .cmi_req  (xip_cmi_req),
  .cmi_ctl  (xip_cmi_ctl),
  .cmi_dat  (xip_cmi_dat),
  .cmi_grt  (xip_cmi_grt)
);

////////////////////////////////////////////////////////////////////////////////
// DMA instance                                                               //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_dma #(
  // port widths
  .DAW      (DAW    )
) dma (
  // system signals
  .clk      (clk_cpu),
  .rst      (rst_cpu),
  // input bus (XIP requests)
  .dma_wen  (dma_wen),
  .dma_ren  (dma_ren),
  .dma_adr  (dma_adr),
  .dma_ben  (dma_ben),
  .dma_wdt  (dma_wdt),
  .dma_rdt  (dma_rdt),
  .dma_wrq  (dma_wrq),
  .dma_err  (dma_err),
  // configuration
  .cfg_m_s  (cfg_m_s),
  .cfg_dma  (cfg_dma),
  .adr_rof  (adr_rof),
  .adr_wof  (adr_wof),
  // DMA task
  .tsk_req  (tsk_req),
  .tsk_ctl  (tsk_ctl),
  .tsk_sts  (tsk_sts),
  .tsk_grt  (tsk_grt),
  // command output
  .cmo_req  (dma_cmo_req),
  .cmo_ctl  (dma_cmo_ctl),
  .cmo_dat  (dma_cmo_dat),
  .cmo_grt  (dma_cmo_grt),
  // command input
  .cmi_req  (dma_cmi_req),
  .cmi_ctl  (dma_cmi_ctl),
  .cmi_dat  (dma_cmi_dat),
  .cmi_grt  (dma_cmi_grt)
);

////////////////////////////////////////////////////////////////////////////////
// arbitration                                                                //
////////////////////////////////////////////////////////////////////////////////

// TODO
assign arb_dmo = tsk_sts[0];
assign arb_dmi = tsk_sts[1];
assign arb_xip = 1'b0;  // TODO

// command output multiplexer
assign cmo_req = arb_xip ? xip_cmo_req : arb_dmo ? dma_cmo_req : reg_cmo_req;
assign cmo_ctl = arb_xip ? xip_cmo_ctl : arb_dmo ? dma_cmo_ctl : reg_cmo_ctl;
assign cmo_dat = arb_xip ? xip_cmo_dat : arb_dmo ? dma_cmo_dat : reg_cmo_dat;
// command output decoder
assign reg_cmo_grt = cmo_grt & ~arb_xip & ~arb_dmo;
assign dma_cmo_grt = cmo_grt & ~arb_xip &  arb_dmo;
assign xip_cmo_grt = cmo_grt &  arb_xip;

// command input demultiplexer
assign reg_cmi_req = cmi_req & ~arb_xip & ~arb_dmo;
assign dma_cmi_req = cmi_req & ~arb_xip &  arb_dmo;
assign xip_cmi_req = cmi_req &  arb_xip;
assign {xip_cmi_ctl, dma_cmi_ctl, reg_cmi_ctl} = {3{cmi_ctl}};
assign {xip_cmi_dat, dma_cmi_dat, reg_cmi_dat} = {3{cmi_dat}};
// command input encoder
assign cmi_grt = arb_xip ? xip_cmi_grt : arb_dmi ? dma_cmi_grt : reg_cmi_grt;

////////////////////////////////////////////////////////////////////////////////
// repack                                                                     //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_rpo #(
  .SDW      (SDW)
) rpo (
  // system signals
  .clk      (clk_cpu),
  .rst      (rst_cpu),
  // configuration  // TODO
  // command output
  .cmd_req  (cmo_req),
  .cmd_ctl  (cmo_ctl),
  .cmd_dat  (cmo_dat),
  .cmd_grt  (cmo_grt),
  // queue output
  .que_req  (qow_req),
  .que_ctl  (qow_ctl),
  .que_dat  (qow_dat),
  .que_grt  (qow_grt)
);

sockit_spi_rpi #(
  .SDW  (SDW)
) rpi (
  // system signals
  .clk      (clk_cpu),
  .rst      (rst_cpu),
  // configuration  // TODO
  // command input
  .cmd_req  (cmi_req),
  .cmd_ctl  (cmi_ctl),
  .cmd_dat  (cmi_dat),
  .cmd_grt  (cmi_grt),
  // queue output
  .que_req  (qir_req),
  .que_ctl  (qir_ctl),
  .que_dat  (qir_dat),
  .que_grt  (qir_grt)
);

////////////////////////////////////////////////////////////////////////////////
// clock domain crossing pipeline (optional) for data register                //
////////////////////////////////////////////////////////////////////////////////

generate if (CDC) begin : cdc

  // data output
  sockit_spi_cdc #(
    .CW       (      1),
    .DW       (QCO+QDW)
  ) cdc_quo (
    // input port
    .cdi_clk  (clk_cpu),
    .cdi_rst  (rst_cpu),
    .cdi_clr  (1'b0),
    .cdi_dat ({qow_ctl,
               qow_dat}),
    .cdi_req  (qow_req),
    .cdi_grt  (qow_grt),
    // output port
    .cdo_clk  (spi_cko),
    .cdo_rst  (rst_spi),
    .cdo_clr  (1'b0),
    .cdo_dat ({qor_ctl,
               qor_dat}),
    .cdo_req  (qor_req),
    .cdo_grt  (qor_grt)
  );

  // data input
  sockit_spi_cdc #(
    .CW       (      1),
    .DW       (QCI+QDW)
  ) cdc_qui (
    // input port
    .cdi_clk  (spi_cki),
    .cdi_rst  (rst_spi),
    .cdi_clr  (1'b0),
    .cdi_dat ({qiw_ctl,
               qiw_dat}),
    .cdi_req  (qiw_req),
    .cdi_grt  (qiw_grt),
    // output port
    .cdo_clk  (clk_cpu),
    .cdo_rst  (rst_cpu),
    .cdo_clr  (1'b0),
    .cdo_dat ({qir_ctl,
               qir_dat}),
    .cdo_req  (qir_req),
    .cdo_grt  (qir_grt)
  );

end else begin : syn

  // data output
  assign qor_req = qow_req;
  assign qor_ctl = qow_ctl;
  assign qor_dat = qow_dat;
  assign qow_grt = qor_grt;

  // data input
  assign qir_req = qiw_req;
  assign qir_ctl = qiw_ctl;
  assign qir_dat = qiw_dat;
  assign qiw_grt = qir_grt;

end endgenerate

////////////////////////////////////////////////////////////////////////////////
// serializer/de-serializer instance                                           //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_ser #(
  .SSW      (SSW),
  .SDW      (SDW)
) ser (
  // system signals
  .clk      (clk_spi),
  .rst      (rst_spi),
  // SPI clocks
  .spi_cko  (spi_cko),
  .spi_cki  (spi_cki),
  // SPI configuration
  .cfg_pol  (cfg_pol),
  .cfg_pha  (cfg_pha),
  .cfg_coe  (cfg_coe),
  .cfg_sse  (cfg_sse),
  .cfg_m_s  (cfg_m_s),
  // output sequence
  .quo_req  (qor_req),
  .quo_ctl  (qor_ctl),
  .quo_dat  (qor_dat),
  .quo_grt  (qor_grt),
  // input sequence
  .qui_req  (qiw_req),
  .qui_ctl  (qiw_ctl),
  .qui_dat  (qiw_dat),
  .qui_grt  (qiw_grt),

  // SCLK (serial clock)
  .spi_sclk_i  (spi_sclk_i),
  .spi_sclk_o  (spi_sclk_o),
  .spi_sclk_e  (spi_sclk_e),
  // SIO  (serial input output) {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  .spi_sio_i   (spi_sio_i),
  .spi_sio_o   (spi_sio_o),
  .spi_sio_e   (spi_sio_e),
  // SS_N (slave select - active low signal)
  .spi_ss_i    (spi_ss_i),
  .spi_ss_o    (spi_ss_o),
  .spi_ss_e    (spi_ss_e)
);

endmodule
