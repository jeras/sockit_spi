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
//  AXI4         BUS     INTERNAL  REPACKAGING   CLOCK     SERIALIZER         //
//  BUSES    INTERFACES   ARBITER                DOMAIN        DE-            //
//                                               CROSSING  SERIALIZER         //
//             -------     -----                                              //
//   xip   --> | XIP | <=> |   |                                              //
//             -------     | a |     -------     -------     -----            //
//                ^        | r | --> | RPO | --> | CDC | --> |   |            //
//                |        | b |     -------     -------     | S |            //
//             -------     | i |                             | E | <=> SPI_*  //
//   reg   <-- | REG | <=> | t |     -------     -------     | R |            //
//             -------     | e | <-- | RPI | <-- | CDC | <-- |   |            //
//             -------     | r |     -------     -------     -----            //
//   dma   --> | DMA | <=> |   |                                              //
//             -------     -----                                              //
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
  axi4_lite.s            axi_reg,
  // XIP interface bus (slave)
  axi4.s                 axi_xip,
  // DMA interface bus (slave)
  axi4.s                 axi_xip,

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

localparam CDW = 32;  // data width

// SPI/XIP/DMA configuration
sockit_spi_pkg::cfg_t spi_cfg;

// address offsets
logic    [31:0] adr_rof;  // address read  offset
logic    [31:0] adr_wof;  // address write offset

// arbitration locks
logic  arb_lko;  // command output multiplexer/decode
logic  arb_lki;  // command input demultiplexer/encoder
logic  arb_xip;  // XIP access to the command interface

typedef sockit_spi_pkg:cmd qc_t;
typedef logic [DW-1:0] qo_t;
typedef logic [DW-1:0] qi_t;

// xip streams
sockit_spi_if #(.DT (qc_t)) scx (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
sockit_spi_if #(.DT (qo_t)) sox (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
sockit_spi_if #(.DT (qi_t)) six (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
// bus (reg/dat) streams
sockit_spi_if #(.DT (qc_t)) scb (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
sockit_spi_if #(.DT (qo_t)) sob (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
sockit_spi_if #(.DT (qi_t)) sib (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
// cdc write
sockit_spi_if #(.DT (qc_t)) qcw (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
sockit_spi_if #(.DT (qo_t)) qow (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
sockit_spi_if #(.DT (qi_t)) qiw (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
// cdc read
sockit_spi_if #(.DT (qr_t)) qcr (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
sockit_spi_if #(.DT (qo_t)) qor (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));
sockit_spi_if #(.DT (qi_t)) qir (.clk (clk_cpu), .clr (1'b0), .rst (rst_cpu));

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
  // AMBA AXI4-lite
  .axi      (axi_reg),
  // SPI/XIP/DMA configuration
  .spi_cfg  (spi_cfg),
  // address offsets
  .adr_rof  (adr_rof),
  .adr_wof  (adr_wof),
  // command output
  .cmc      (reg_cmc),
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
  // AMBA AXI4
  .axi      (axi_xip),
  // configuration
  .spi_cfg  (spi_cfg),
  .adr_rof  (adr_rof),
  .adr_wof  (adr_wof),
  // streams
  .cmc      (xip_cmc),
  .cmo      (xip_cmo),
  .cmi      (xip_cmi)
);

////////////////////////////////////////////////////////////////////////////////
// DMA instance                                                               //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_dma #(
  // port widths
  .DAW      (DAW    )
) dma (
  // AMBA AXI4
  .axi      (axi_dma),
  // configuration
  .spi_cfg  (spi_cfg),
  // streams
  .cmo      (dma_cmo),
  .cmi      (dma_cmi)
);

////////////////////////////////////////////////////////////////////////////////
// arbitration                                                                //
////////////////////////////////////////////////////////////////////////////////

// TODO
assign arb_xip = 1'b0;  // TODO

// command output multiplexer
assign qow.vld = arb_xip ? xip_cmo.vld : arb_lko ? dma_cmo.vld : reg_cmo.vld;
assign qow.dat = arb_xip ? xip_cmo.dat : arb_lko ? dma_cmo.dat : reg_cmo.dat;
// command output decoder
assign reg_cmo.rdy = qow.rdy & ~arb_xip & ~arb_lko;
assign dma_cmo.rdy = qow.rdy & ~arb_xip &  arb_lko;
assign xip_cmo.rdy = qow.rdy &  arb_xip;

// command input demultiplexer
assign reg_cmi.vld = qir.vld & ~arb_xip & ~arb_lki;
assign dma_cmi.vld = qir.vld & ~arb_xip &  arb_lki;
assign xip_cmi.vld = qir.vld &  arb_xip;
assign {xip_cmi.dat, dma_cmi.dat} = {2{qir.dat}};
// command input encoder
assign qir.rdy = arb_xip ? xip_cmi.rdy : arb_lki ? dma_cmi.rdy : reg_cmi.rdy;

////////////////////////////////////////////////////////////////////////////////
// clock domain crossing pipeline (optional) for data register                //
////////////////////////////////////////////////////////////////////////////////

generate if (CDC) begin : cdc

  // control
  sockit_spi_cdc #(
    .CW       (   1),
    .DT       (qc_t)
  ) cdc_quc (
    .cdi      (qcw),
    .cdo      (qcr)
  );

  // data output
  sockit_spi_cdc #(
    .CW       (   1),
    .DT       (qo_t)
  ) cdc_quo (
    .cdi      (qow),
    .cdo      (qor)
  );

  // data input
  sockit_spi_cdc #(
    .CW       (   1),
    .DT       (qi_t)
  ) cdc_qui (
    .cdi      (qiw),
    .cdo      (qir)
  );

end else begin : syn

  // command
  assign qcr.vld = qcw.vld;
  assign qcr.dat = qcw.dat;
  assign qcw.rdy = qcr.rdy;

  // data output
  assign qor.vld = qow.vld;
  assign qor.dat = qow.dat;
  assign qow.rdy = qor.rdy;

  // data input
  assign qir.vld = qiw.vld;
  assign qir.dat = qiw.dat;
  assign qiw.rdy = qir.rdy;

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
  // queue streams
  .quc      (qcr),
  .quo      (qor),
  .qui      (qiw),

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
