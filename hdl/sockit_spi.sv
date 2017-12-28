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
  input  logic           clk_cpu,     // clock for CPU interface
  input  logic           rst_cpu,     // reset for CPU interface
  input  logic           clk_spi,     // clock for SPI IO
  input  logic           rst_spi,     // reset for SPI IO
  // registers interface bus (slave)
  input  logic           reg_wen,     // write enable
  input  logic           reg_ren,     // read enable
  input  logic     [2:0] reg_adr,     // address
  input  logic    [31:0] reg_wdt,     // write data
  output logic    [31:0] reg_rdt,     // read data
  output logic           reg_wrq,     // wait request
  output logic           reg_err,     // error response
  output logic           reg_irq,     // interrupt request
  // XIP interface bus (slave)
  input  logic           xip_wen,     // write enable
  input  logic           xip_ren,     // read enable
  input  logic [XAW-1:0] xip_adr,     // address
  input  logic     [3:0] xip_ben,     // byte enable
  input  logic    [31:0] xip_wdt,     // write data
  output logic    [31:0] xip_rdt,     // read data
  output logic           xip_wrq,     // wait request
  output logic           xip_err,     // error response
  // DMA interface bus (master)
  output logic           dma_wen,     // write enable
  output logic           dma_ren,     // read enable
  output logic [DAW-1:0] dma_adr,     // address
  output logic     [3:0] dma_ben,     // byte enable
  output logic    [31:0] dma_wdt,     // write data
  input  logic    [31:0] dma_rdt,     // read data
  input  logic           dma_wrq,     // wait request
  input  logic           dma_err,     // error response

  // SPI signals (at a higher level should be connected to tristate IO pads)
  // serial clock
  input  logic           spi_sclk_i,  // input (clock loopback)
  output logic           spi_sclk_o,  // output
  output logic           spi_sclk_e,  // output enable
  // serial input output SIO[3:0] or {HOLD_n, WP_n, MISO, MOSI/3logic-bidir}
  input  logic     [3:0] spi_sio_i,   // input
  output logic     [3:0] spi_sio_o,   // output
  output logic     [3:0] spi_sio_e,   // output enable
  // active low slave select signal
  input  logic [SSW-1:0] spi_ss_i,    // input  (requires inverter at the pad)
  output logic [SSW-1:0] spi_ss_o,    // output (requires inverter at the pad)
  output logic [SSW-1:0] spi_ss_e     // output enable
);

////////////////////////////////////////////////////////////////////////////////
// local parameters and signals                                               //
////////////////////////////////////////////////////////////////////////////////

// command parameters
localparam CCO =          5+7;  // control output width
localparam CCI =            4;  // control  input width
localparam CDW =           32;  // data width

// queue parameters
localparam QCO =        SDL+7;  // control output width
localparam QCI =            4;  // control  input width
localparam QDW =        4*SDW;  // data width

// SPI/XIP/DMA configuration
logic    [31:0] spi_cfg;

// address offsets
logic    [31:0] adr_rof;  // address read  offset
logic    [31:0] adr_wof;  // address write offset

// arbitration locks
logic  arb_lko;  // command output multiplexer/decode
logic  arb_lki;  // command input demultiplexer/encoder
logic  arb_xip;  // XIP access to the command interface

// command output
logic           reg_cmo_vld, xip_cmo_vld, dma_cmo_vld,  cmo_vld;  // valid
logic [CCO-1:0] reg_cmo_ctl, xip_cmo_ctl, dma_cmo_ctl,  cmo_ctl;  // control
logic [CDW-1:0] reg_cmo_dat, xip_cmo_dat, dma_cmo_dat,  cmo_dat;  // data
logic           reg_cmo_rdy, xip_cmo_rdy, dma_cmo_rdy,  cmo_rdy;  // ready
// command input
logic           reg_cmi_vld, xip_cmi_vld, dma_cmi_vld,  cmi_vld;  // valid
logic [CCI-1:0] reg_cmi_ctl, xip_cmi_ctl, dma_cmi_ctl,  cmi_ctl;  // control
logic [CDW-1:0] reg_cmi_dat, xip_cmi_dat, dma_cmi_dat,  cmi_dat;  // data
logic           reg_cmi_rdy, xip_cmi_rdy, dma_cmi_rdy,  cmi_rdy;  // ready

// queue output
logic           qow_vld, qor_vld;  // valid
logic [QCO-1:0] qow_ctl, qor_ctl;  // control
logic [QDW-1:0] qow_dat, qor_dat;  // data
logic           qow_rdy, qor_rdy;  // ready
// queue input
logic           qir_vld, qiw_vld;  // valid
logic [QCI-1:0] qir_ctl, qiw_ctl;  // control
logic [QDW-1:0] qir_dat, qiw_dat;  // data
logic           qir_rdy, qiw_rdy;  // ready

// DMA task interface
logic           tsk_vld;  // valid
logic    [31:0] tsk_ctl;  // control
logic    [31:0] tsk_sts;  // status
logic           tsk_rdy;  // ready

// SPI clocks
logic           spi_cko;  // output registers
logic           spi_cki;  // input  registers

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
  .spi_cfg  (spi_cfg),
  // address offsets
  .adr_rof  (adr_rof),
  .adr_wof  (adr_wof),
  // command output
  .cmo_vld  (reg_cmo_vld),
  .cmo_ctl  (reg_cmo_ctl),
  .cmo_dat  (reg_cmo_dat),
  .cmo_rdy  (reg_cmo_rdy),
  // command input
  .cmi_vld  (reg_cmi_vld),
  .cmi_ctl  (reg_cmi_ctl),
  .cmi_dat  (reg_cmi_dat),
  .cmi_rdy  (reg_cmi_rdy),
  // DMA task interface
  .tsk_vld  (tsk_vld),
  .tsk_ctl  (tsk_ctl),
  .tsk_sts  (tsk_sts),
  .tsk_rdy  (tsk_rdy)
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
  .spi_cfg  (spi_cfg),
  .adr_rof  (adr_rof),
  .adr_wof  (adr_wof),
  // command output
  .cmo_vld  (xip_cmo_vld),
  .cmo_ctl  (xip_cmo_ctl),
  .cmo_dat  (xip_cmo_dat),
  .cmo_rdy  (xip_cmo_rdy),
  // command input
  .cmi_vld  (xip_cmi_vld),
  .cmi_ctl  (xip_cmi_ctl),
  .cmi_dat  (xip_cmi_dat),
  .cmi_rdy  (xip_cmi_rdy)
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
  .spi_cfg  (spi_cfg),
  .adr_rof  (adr_rof),
  .adr_wof  (adr_wof),
  // DMA task
  .tsk_vld  (tsk_vld),
  .tsk_ctl  (tsk_ctl),
  .tsk_sts  (tsk_sts),
  .tsk_rdy  (tsk_rdy),
  // arbiter locks
  .arb_lko  (arb_lko),
  .arb_lki  (arb_lki),
  // command output
  .cmo_vld  (dma_cmo_vld),
  .cmo_ctl  (dma_cmo_ctl),
  .cmo_dat  (dma_cmo_dat),
  .cmo_rdy  (dma_cmo_rdy),
  // command input
  .cmi_vld  (dma_cmi_vld),
  .cmi_ctl  (dma_cmi_ctl),
  .cmi_dat  (dma_cmi_dat),
  .cmi_rdy  (dma_cmi_rdy)
);

////////////////////////////////////////////////////////////////////////////////
// arbitration                                                                //
////////////////////////////////////////////////////////////////////////////////

// TODO
assign arb_xip = 1'b0;  // TODO

// command output multiplexer
assign cmo_vld = arb_xip ? xip_cmo_vld : arb_lko ? dma_cmo_vld : reg_cmo_vld;
assign cmo_ctl = arb_xip ? xip_cmo_ctl : arb_lko ? dma_cmo_ctl : reg_cmo_ctl;
assign cmo_dat = arb_xip ? xip_cmo_dat : arb_lko ? dma_cmo_dat : reg_cmo_dat;
// command output decoder
assign reg_cmo_rdy = cmo_rdy & ~arb_xip & ~arb_lko;
assign dma_cmo_rdy = cmo_rdy & ~arb_xip &  arb_lko;
assign xip_cmo_rdy = cmo_rdy &  arb_xip;

// command input demultiplexer
assign reg_cmi_vld = cmi_vld & ~arb_xip & ~arb_lki;
assign dma_cmi_vld = cmi_vld & ~arb_xip &  arb_lki;
assign xip_cmi_vld = cmi_vld &  arb_xip;
assign {xip_cmi_ctl, dma_cmi_ctl, reg_cmi_ctl} = {3{cmi_ctl}};
assign {xip_cmi_dat, dma_cmi_dat, reg_cmi_dat} = {3{cmi_dat}};
// command input encoder
assign cmi_rdy = arb_xip ? xip_cmi_rdy : arb_lki ? dma_cmi_rdy : reg_cmi_rdy;

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
  .cmd_vld  (cmo_vld),
  .cmd_ctl  (cmo_ctl),
  .cmd_dat  (cmo_dat),
  .cmd_rdy  (cmo_rdy),
  // queue output
  .que_vld  (qow_vld),
  .que_ctl  (qow_ctl),
  .que_dat  (qow_dat),
  .que_rdy  (qow_rdy)
);

sockit_spi_rpi #(
  .SDW  (SDW)
) rpi (
  // system signals
  .clk      (clk_cpu),
  .rst      (rst_cpu),
  // configuration  // TODO
  // command input
  .cmd_vld  (cmi_vld),
  .cmd_ctl  (cmi_ctl),
  .cmd_dat  (cmi_dat),
  .cmd_rdy  (cmi_rdy),
  // queue output
  .que_vld  (qir_vld),
  .que_ctl  (qir_ctl),
  .que_dat  (qir_dat),
  .que_rdy  (qir_rdy)
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
    .cdi_vld  (qow_vld),
    .cdi_rdy  (qow_rdy),
    // output port
    .cdo_clk  (spi_cko),
    .cdo_rst  (rst_spi),
    .cdo_clr  (1'b0),
    .cdo_dat ({qor_ctl,
               qor_dat}),
    .cdo_vld  (qor_vld),
    .cdo_rdy  (qor_rdy)
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
    .cdi_vld  (qiw_vld),
    .cdi_rdy  (qiw_rdy),
    // output port
    .cdo_clk  (clk_cpu),
    .cdo_rst  (rst_cpu),
    .cdo_clr  (1'b0),
    .cdo_dat ({qir_ctl,
               qir_dat}),
    .cdo_vld  (qir_vld),
    .cdo_rdy  (qir_rdy)
  );

end else begin : syn

  // data output
  assign qor_vld = qow_vld;
  assign qor_ctl = qow_ctl;
  assign qor_dat = qow_dat;
  assign qow_rdy = qor_rdy;

  // data input
  assign qir_vld = qiw_vld;
  assign qir_ctl = qiw_ctl;
  assign qir_dat = qiw_dat;
  assign qiw_rdy = qir_rdy;

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
  .spi_cfg  (spi_cfg),
  // output queue
  .quo_vld  (qor_vld),
  .quo_ctl  (qor_ctl),
  .quo_dat  (qor_dat),
  .quo_rdy  (qor_rdy),
  // input queue
  .qui_vld  (qiw_vld),
  .qui_ctl  (qiw_ctl),
  .qui_dat  (qiw_dat),
  .qui_rdy  (qiw_rdy),

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

endmodule: sockit_spi
