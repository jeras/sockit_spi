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
//  Address space                                                             //
//                                                                            //
//  adr | reg name, short description                                         //
// -----+-------------------------------------------------------------------- //
//  0x0 | spi_cfg - SPI configuration                                         //
//  0x1 | spi_par - SPI parameterization (synthesis parameters, read only)    //
//  0x2 | spi_ctl - SPI control                                               //
//  0x3 | spi_dat - SPI data                                                  //
//  0x4 | xip_cfg - XIP configuration                                         //
//  0x5 | dma_cfg - DMA configuration                                         //
//  0x6 | adr_rof - address read  offset                                      //
//  0x7 | adr_wof - address write offset                                      //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi_reg #(
  // configuretion
  parameter CFG_RST = 32'h00000000,  // configuration register reset value
  parameter CFG_MSK = 32'hffffffff,  // configuration register implementation mask
  parameter XIP_RST = 32'h00000000,  // XIP configuration register reset value
  parameter XIP_MSK = 32'h00000000,  // XIP configuration register implentation mask
  parameter DMA_RST = 32'h00000000,  // DMA configuration register reset value
  parameter DMA_MSK = 32'h00000000,  // DMA configuration register implentation mask
  // port widths
  parameter XAW     =           24,  // XIP address width
  parameter CCO     =          5+6,  // command control output width
  parameter CCI     =            4,  // command control  input width
  parameter CDW     =           32   // command data width
)(
  // system signals (used by the CPU interface)
  input  wire           clk,      // clock for CPU interface
  input  wire           rst,      // reset for CPU interface
  // bus interface
  input  wire           reg_wen,  // write enable
  input  wire           reg_ren,  // read enable
  input  wire     [2:0] reg_adr,  // address
  input  wire    [31:0] reg_wdt,  // write data
  output reg     [31:0] reg_rdt,  // read data
  output reg            reg_wrq,  // wait request
  output wire           reg_irq,  // interrupt request
  // SPI configuration
  output reg            cfg_pol,  // clock polarity
  output reg            cfg_pha,  // clock phase
  output reg            cfg_coe,  // clock output enable
  output reg            cfg_sse,  // slave select output enable
  output reg            cfg_m_s,  // mode (0 - slave, 1 - master)
  output reg            cfg_dir,  // shift direction (0 - lsb first, 1 - msb first)
  // XIP configuration, DMA configuration, address offsets
  output reg     [31:0] xip_cfg,  // XIP configuration
  output reg     [31:0] dma_cfg,  // DMA configuration
  output reg     [31:0] adr_rof,  // address read  offset
  output reg     [31:0] adr_wof,  // address write offset
  // arbitration
  output wire     [1:0] arb_sel,  // arbiter select
  // command output
  output wire           cmo_req,  // request
  output wire [CCO-1:0] cmo_ctl,  // control
  output wire [CDW-1:0] cmo_dat,  // data
  input  wire           cmo_grt,  // grant
  // command input
  input  wire           cmi_req,  // request
  input  wire [CCI-1:0] cmi_ctl,  // control
  input  wire [CDW-1:0] cmi_dat,  // data
  output wire           cmi_grt   // grant
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// decoded register access signals
wire  wen_ctl, ren_ctl;  // control
wire  wen_dat, ren_dat;  // data

wire    [31:0] spi_cfg;  // SPI configuration
wire    [31:0] spi_par;  // SPI parameterization
wire    [31:0] spi_ctl;  // SPI control

wire           cmo_trn;
wire           cmi_trn;

reg     [31:0] cmd_wdt;
reg     [31:0] cmd_rdt;

// data
reg            dat_wld;  // write load
reg            dat_rld;  // read  load

////////////////////////////////////////////////////////////////////////////////
// register decoder                                                           //
////////////////////////////////////////////////////////////////////////////////

// register write/read access signals
assign {wen_ctl, ren_ctl} = {reg_wen, reg_ren} & {2{(reg_adr == 3'd2) & ~reg_wrq}};  // control
assign {wen_dat, ren_dat} = {reg_wen, reg_ren} & {2{(reg_adr == 3'd3) & ~reg_wrq}};  // data

// read data
always @ (*)
case (reg_adr)
  3'd0 : reg_rdt = spi_cfg;  // SPI configuration
  3'd1 : reg_rdt = spi_par;  // SPI parameterization
  3'd2 : reg_rdt = spi_ctl;  // SPI control
  3'd3 : reg_rdt = cmd_rdt;  // SPI data
  3'd4 : reg_rdt = xip_cfg;  // XIP configuration
  3'd5 : reg_rdt = dma_cfg;  // DMA configuration
  3'd6 : reg_rdt = adr_rof;  // address read  offset
  3'd7 : reg_rdt = adr_wof;  // address write offset
endcase

// wait request
always @ (*)
case (reg_adr)
  3'd0 : reg_wrq = 1'b0;                                 // SPI configuration
  3'd1 : reg_wrq = 1'b0;                                 // SPI parameterization
  3'd2 : reg_wrq = reg_wen & ~cmo_grt;                   // SPI control
  3'd3 : reg_wrq = reg_wen & 1'b0 | reg_ren & ~dat_rld;  // SPI data
  3'd4 : reg_wrq = 1'b0;                                 // XIP configuration
  3'd5 : reg_wrq = 1'b0;                                 // DMA configuration
  3'd6 : reg_wrq = 1'b0;                                 // address read  offset
  3'd7 : reg_wrq = 1'b0;                                 // address write offset
endcase

////////////////////////////////////////////////////////////////////////////////
// interrupt                                                                  //
////////////////////////////////////////////////////////////////////////////////

// interrupt
assign reg_irq = 1'b0; // TODO

////////////////////////////////////////////////////////////////////////////////
// configuration registers                                                    //
////////////////////////////////////////////////////////////////////////////////

// SPI configuration (read access)
assign spi_cfg = {26'h0, cfg_dir, cfg_m_s, cfg_sse, cfg_coe, cfg_pol, cfg_pha};

// SPI parameterization (read access)
assign spi_par =  32'h0;

// spi control
assign spi_ctl =  32'h0; // TODO

// SPI configuration (write access)
always @(posedge clk, posedge rst)
if (rst) begin
  {cfg_dir, cfg_m_s, cfg_sse, cfg_coe, cfg_pol, cfg_pha} <= CFG_RST [ 5: 0];
end else if (reg_wen & (reg_adr == 3'd0)) begin
  {cfg_dir, cfg_m_s, cfg_sse, cfg_coe, cfg_pol, cfg_pha} <= reg_wdt [ 5: 0];
end

// XIP configuration, DMA configuration, address offsets
always @(posedge clk, posedge rst)
if (rst) begin
  xip_cfg <= XIP_RST [31: 0];
  dma_cfg <= XIP_RST [31: 0];
  adr_rof <= XIP_RST [31: 0];
  adr_wof <= XIP_RST [31: 0];
end else if (reg_wen) begin
  if (reg_adr == 3'd4)  xip_cfg <= reg_wdt;
  if (reg_adr == 3'd5)  dma_cfg <= reg_wdt;
  if (reg_adr == 3'd6)  adr_rof <= reg_wdt;
  if (reg_adr == 3'd7)  adr_wof <= reg_wdt;
end

////////////////////////////////////////////////////////////////////////////////
// arbitration                                                                //
////////////////////////////////////////////////////////////////////////////////

assign arb_sel = 2'b00;

////////////////////////////////////////////////////////////////////////////////
// command output                                                             //
////////////////////////////////////////////////////////////////////////////////

// command output transfer
assign cmo_trn = cmo_req & cmo_grt;

// data output
always @(posedge clk)
if (wen_dat)  cmd_wdt <= reg_wdt;

// data output load status
always @(posedge clk, posedge rst)
if (rst)             dat_wld <= 1'b0;
else begin
  if      (wen_dat)  dat_wld <= 1'b1;
  else if (cmo_trn)  dat_wld <= 1'b0;
end

// command output
assign cmo_req = wen_ctl;
assign cmo_dat = cmd_wdt;
assign cmo_ctl = {reg_wdt[12:8], reg_wdt[5:0]};

////////////////////////////////////////////////////////////////////////////////
// command input register                                                     //
////////////////////////////////////////////////////////////////////////////////

// command input transfer
assign cmi_trn = cmi_req & cmi_grt;

// data input
always @(posedge clk)
if (cmi_trn)  cmd_rdt <= cmi_dat;

// data input load status
always @(posedge clk, posedge rst)
if (rst)             dat_rld <= 1'b0;
else begin
  if      (cmi_trn)  dat_rld <= 1'b1;
  else if (ren_dat)  dat_rld <= 1'b0;
end

// command input transfer grant
assign cmi_grt = ~dat_rld;

endmodule
