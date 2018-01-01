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
  // configuration/parameterization register parameters
  sockit_spi_pkg::cfg_t RST = 32'h00000000,  // reset value
  sockit_spi_pkg::cfg_t MSK = 32'hffffffff,  // implementation mask
  // AXI parameters
  int unsigned   XAW =         24,  // XIP address width
  int unsigned   OFF = 24'h000000,  // AXI address offset reset value
  logic [32-1:0] NOP = 32'h00000000,  // no operation instruction for the given CPU
  // SPI protocol parameters
  int unsigned SSW =    8,  // slave select width
  bit          CDC = 1'b0   // implement clock domain crossing
)(
  // system signals (used by SPI interface)
  input  logic   clk_spi,  // clock for SPI IO
  input  logic   rst_spi,  // reset for SPI IO
  // AMBA AXI4 slave interfaces
  axi4_lite_if.s axi_reg,  // registers
  axi4_if.s      axi_dma,  // DMA
  axi4_if.s      axi_xip,  // XIP
  // SPI signals (at a higher level should be connected to tristate IO pads)
  spi_if.m       spi_inf
);

////////////////////////////////////////////////////////////////////////////////
// local parameters and signals                                               //
////////////////////////////////////////////////////////////////////////////////

localparam int unsigned DW = 32;  // data width

// type definitions
typedef sockit_spi_pkg::cmd_t scw_t;
typedef logic [DW-1:0] sdw_t;
typedef logic [DW-1:0] sdr_t;

// SPI/XIP/DMA configuration
sockit_spi_pkg::cfg_t spi_cfg;

// address offset
logic [XAW-1:0] adr_off;

// TODO: check clocks and resets, only important, if there is clock gating

// REG/DMA streams
sockit_spi_if #(.DT (scw_t)) scw_reg (.clk (axi_xip.ACLK), .clr (1'b0), .rst (axi_xip.ARESETn));
sockit_spi_if #(.DT (sdw_t)) sdw_dma (.clk (axi_xip.ACLK), .clr (1'b0), .rst (axi_xip.ARESETn));
sockit_spi_if #(.DT (sdr_t)) sdr_dma (.clk (axi_xip.ACLK), .clr (1'b0), .rst (axi_xip.ARESETn));
// XIP streams
sockit_spi_if #(.DT (scw_t)) scw_xip (.clk (axi_xip.ACLK), .clr (1'b0), .rst (axi_xip.ARESETn));
sockit_spi_if #(.DT (sdw_t)) sdw_xip (.clk (axi_xip.ACLK), .clr (1'b0), .rst (axi_xip.ARESETn));
sockit_spi_if #(.DT (sdr_t)) sdr_xip (.clk (axi_xip.ACLK), .clr (1'b0), .rst (axi_xip.ARESETn));
// CDC (Clock Domain aXi) streams
sockit_spi_if #(.DT (scw_t)) scw_cdx (.clk (axi_xip.ACLK), .clr (1'b0), .rst (axi_xip.ARESETn));
sockit_spi_if #(.DT (sdw_t)) sdw_cdx (.clk (axi_xip.ACLK), .clr (1'b0), .rst (axi_xip.ARESETn));
sockit_spi_if #(.DT (sdr_t)) sdr_cdx (.clk (axi_xip.ACLK), .clr (1'b0), .rst (axi_xip.ARESETn));
// CDC (Clock Domain Spi) streams
sockit_spi_if #(.DT (scw_t)) scw_cds (.clk (clk_spi), .clr (1'b0), .rst (rst_spi));
sockit_spi_if #(.DT (sdw_t)) sdw_cds (.clk (clk_spi), .clr (1'b0), .rst (rst_spi));
sockit_spi_if #(.DT (sdr_t)) sdr_cds (.clk (clk_spi), .clr (1'b0), .rst (rst_spi));

////////////////////////////////////////////////////////////////////////////////
// REG instance                                                               //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_reg #(
  // configuration/parameterization
  .RST      (RST),
  .MSK      (MSK),
  // XIP
  .XAW      (XAW),
  .OFF      (OFF)
) rgs (
  // AMBA AXI4-lite
  .axi      (axi_reg),
  // SPI/XIP/DMA configuration
  .cfg      (spi_cfg),
  // address offsets
  .off      (adr_off),
  // command stream
  .scw      (scw_reg)
);

////////////////////////////////////////////////////////////////////////////////
// DMA instance                                                               //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_dma dma (
  // AMBA AXI4
  .axi      (axi_dma),
  // data streams
  .sdw      (sdw_dma),
  .sdr      (sdr_dma)
);

////////////////////////////////////////////////////////////////////////////////
// XIP instance                                                               //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_xip #(
  .NOP      (NOP),
  .XAW      (XAW)
) xip (
  // AMBA AXI4
  .axi      (axi_xip),
  // configuration
  .cfg      (spi_cfg),
  .off      (adr_off),
  // command/data streams
  .scw      (scw_xip),
  .sdw      (sdw_xip),
  .sdr      (sdr_xip)
);

////////////////////////////////////////////////////////////////////////////////
// multiplexer/fork between XIP and REG+DMA                                   //
////////////////////////////////////////////////////////////////////////////////

assign arb_xip = 1'b0;  // TODO: should come from a configuration register

//                                      select         port 0          port 1          common port
sockit_spi_mux #(.DT (scw_t)) mux_scw (.sel (arb_xip), .si0 (scw_xip), .si1 (scw_reg), .sto (scw_cdx));  // command
sockit_spi_mux #(.DT (sdw_t)) mux_sdw (.sel (arb_xip), .si0 (sdw_xip), .si1 (sdw_dma), .sto (sdw_cdx));  // data write
sockit_spi_frk #(.DT (sdr_t)) frk_sdw (.sel (arb_xip), .so0 (sdr_xip), .so1 (sdr_dma), .sti (sdr_cdx));  // data read

////////////////////////////////////////////////////////////////////////////////
// clock domain crossing pipeline (optional) for data register                //
////////////////////////////////////////////////////////////////////////////////

// for data read path CDC input and output ports are switched

generate if (CDC) begin : cdc

sockit_spi_cdc #(.CW (1), .DT (scw_t)) cdc_scw (.cdi (scw_cdx), .cdo (scw_cds));  // control
sockit_spi_cdc #(.CW (1), .DT (sdw_t)) cdc_sdw (.cdi (sdw_cdx), .cdo (sdw_cds));  // data write
sockit_spi_cdc #(.CW (1), .DT (sdr_t)) cdc_sdr (.cdo (sdr_cdx), .cdi (sdr_cds));  // data read

end else begin : syn

sockit_spi_pas #(.CW (1), .DT (scw_t)) pas_scw (.cdi (scw_cdx), .cdo (scw_cds));  // control
sockit_spi_pas #(.CW (1), .DT (sdw_t)) pas_sdw (.cdi (sdw_cdx), .cdo (sdw_cds));  // data write
sockit_spi_pas #(.CW (1), .DT (sdr_t)) pas_sdr (.cdo (sdr_cdx), .cdi (sdr_cds));  // data read

end endgenerate

////////////////////////////////////////////////////////////////////////////////
// serializer/de-serializer instance                                           //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_ser #(
  .SSW      (SSW)
) ser (
  // system signals
  .clk      (clk_spi),
  .rst      (rst_spi),
  // SPI configuration
  .spi_cfg  (spi_cfg),
  // command/data streams
  .quc      (qcr),
  .quo      (qor),
  .qui      (qiw),
  // SPI interface
  .spi      (spi_inf)
);

endmodule: sockit_spi
