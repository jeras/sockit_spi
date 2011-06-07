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
  // configuration (register reset values and masks)
  parameter CFG_RST = 32'h00000000,  // configuration register reset value
  parameter CFG_MSK = 32'hffffffff,  // configuration register implementation mask
  parameter ADR_ROF = 32'h00000000,  // address write offset
  parameter ADR_WOF = 32'h00000000,  // address read  offset
  //
  parameter NOP     = 32'h00000000,  // no operation instuction for the given CPU
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

// buffer parameters
localparam BCO =        SDL+7;  // control output width
localparam BCI =            4;  // control  input width
localparam BDW =        4*SDW;  // data width

// arbitration
wire     [1:0] arb_sel;

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

// buffer output
wire           bow_req, bor_req;  // request
wire [BCO-1:0] bow_ctl, bor_ctl;  // control
wire [BDW-1:0] bow_dat, bor_dat;  // data
wire           bow_grt, bor_grt;  // grant
// buffer input
wire           bir_req, biw_req;  // request
wire [BCI-1:0] bir_ctl, biw_ctl;  // control
wire [BDW-1:0] bir_dat, biw_dat;  // data
wire           bir_grt, biw_grt;  // grant

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
  // arbitrstion
  .arb_sel  (arb_sel),
  // command output
  .cmo_req  (reg_cmo_req),
  .cmo_ctl  (reg_cmo_ctl),
  .cmo_dat  (reg_cmo_dat),
  .cmo_grt  (reg_cmo_grt),
  // command input
  .cmi_req  (reg_cmi_req),
  .cmi_ctl  (reg_cmi_ctl),
  .cmi_dat  (reg_cmi_dat),
  .cmi_grt  (reg_cmi_grt)
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
  .cfg_dma  (cfg_dma),
  .adr_rof  (adr_rof),
  .adr_wof  (adr_wof),
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
// arbiteration                                                               //
////////////////////////////////////////////////////////////////////////////////

// command output multiplexer
assign cmo_req = arb_sel[1] ? (arb_sel[0] ? xip_cmo_req : dma_cmo_req) : reg_cmo_req;
assign cmo_ctl = arb_sel[1] ? (arb_sel[0] ? xip_cmo_ctl : dma_cmo_ctl) : reg_cmo_ctl;
assign cmo_dat = arb_sel[1] ? (arb_sel[0] ? xip_cmo_dat : dma_cmo_dat) : reg_cmo_dat;
// command output decoder
assign reg_cmo_grt = cmo_grt & (arb_sel[1] == 1'b0 );
assign dma_cmo_grt = cmo_grt & (arb_sel    == 2'b10);
assign xip_cmo_grt = cmo_grt & (arb_sel    == 2'b11);

// command input demultiplexer
assign {xip_cmi_req, dma_cmi_req, reg_cmi_req} = {3{cmi_req}};
assign {xip_cmi_ctl, dma_cmi_ctl, reg_cmi_ctl} = {3{cmi_ctl}};
assign {xip_cmi_dat, dma_cmi_dat, reg_cmi_dat} = {3{cmi_dat}};
// command input encoder
assign cmi_grt = arb_sel[1] ? (arb_sel[0] ? xip_cmi_grt : dma_cmi_grt) : reg_cmi_grt;

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
  // buffer output
  .buf_req  (bow_req),
  .buf_ctl  (bow_ctl),
  .buf_dat  (bow_dat),
  .buf_grt  (bow_grt)
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
  // buffer output
  .buf_req  (bir_req),
  .buf_ctl  (bir_ctl),
  .buf_dat  (bir_dat),
  .buf_grt  (bir_grt)
);

////////////////////////////////////////////////////////////////////////////////
// clock domain crossing pipeline (optional) for data register                //
////////////////////////////////////////////////////////////////////////////////

generate if (CDC) begin : cdc

  // data output
  sockit_spi_cdc #(
    .CW       (      1),
    .DW       (BCO+BDW)
  ) cdc_bfo (
    // input port
    .cdi_clk  (clk_cpu),
    .cdi_rst  (rst_cpu),
    .cdi_pli  (bow_req),
    .cdi_dat ({bow_ctl,
               bow_dat}),
    .cdi_plo  (bow_grt),
    // output port
    .cdo_clk  (spi_cko),
    .cdo_rst  (rst_spi),
    .cdo_plo  (bor_req),
    .cdo_dat ({bor_ctl,
               bor_dat}),
    .cdo_pli  (bor_grt)
  );

  // data input
  sockit_spi_cdc #(
    .CW       (      1),
    .DW       (BCI+BDW)
  ) cdc_bfi (
    // input port
    .cdi_clk  (spi_cki),
    .cdi_rst  (rst_spi),
    .cdi_pli  (biw_req),
    .cdi_dat ({biw_ctl,
               biw_dat}),
    .cdi_plo  (biw_grt),
    // output port
    .cdo_clk  (clk_cpu),
    .cdo_rst  (rst_cpu),
    .cdo_plo  (bir_req),
    .cdo_dat ({bir_ctl,
               bir_dat}),
    .cdo_pli  (bir_grt)
  );

end else begin : syn

  // data output
  assign bor_req = bow_req;
  assign bor_ctl = bow_ctl;
  assign bor_dat = bow_dat;
  assign bow_grt = bor_grt;

  // data input
  assign bir_req = biw_req;
  assign bir_ctl = biw_ctl;
  assign bir_dat = biw_dat;
  assign biw_grt = bir_grt;

end endgenerate

////////////////////////////////////////////////////////////////////////////////
// serializer/deserializer instance                                           //
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
  // output buffer
  .bfo_req  (bor_req),
  .bfo_ctl  (bor_ctl),
  .bfo_dat  (bor_dat),
  .bfo_grt  (bor_grt),
  // input buffer
  .bfi_req  (biw_req),
  .bfi_ctl  (biw_ctl),
  .bfi_dat  (biw_dat),
  .bfi_grt  (biw_grt),

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
