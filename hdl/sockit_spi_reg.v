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

module sockit_spi_reg #(
  // configuretion
  parameter CFG_RST = 32'h00000000,  // configuration register reset value
  parameter CFG_MSK = 32'hffffffff,  // configuration register implementation mask
  parameter XIP_RST = 32'h00000000,  // XIP configuration register reset value
  parameter XIP_MSK = 32'h00000001,  // XIP configuration register implentation mask
  // port widths
  parameter XAW     =           24,  // XIP address width
  parameter SSW     =            8,  // slave select width
  parameter CCO     =      5+SSW+7,  // command control output width
  parameter CCI     =            3,  // command control  input width
  parameter CDW     =           32   // command data width
)(
  // system signals (used by the CPU interface)
  input  wire           clk,      // clock for CPU interface
  input  wire           rst,      // reset for CPU interface
  // bus interface
  input  wire           reg_wen,  // write enable
  input  wire           reg_ren,  // read enable
  input  wire     [1:0] reg_adr,  // address
  input  wire    [31:0] reg_wdt,  // write data
  output wire    [31:0] reg_rdt,  // read data
  output wire           reg_wrq,  // wait request
  output wire           reg_irq,  // interrupt request
  // configuration
  // command output
  output wire           cmo_req,  // request
  output wire [CCO-1:0] cmo_ctl,  // control
  output wire [CDW-1:0] cmo_dat,  // data
  input  wire           cmo_grt,  // grant
  // command input
  output wire           cmi_req,  // request
  input  wire [CCI-1:0] cmi_ctl,  // control
  input  wire [CDW-1:0] cmi_dat,  // data
  input  wire           cmi_grt   // grant
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// configuration registers
reg            cfg_hle;  // hold output enable
reg            cfg_hlo;  // hold output
reg            cfg_wpe;  // write protect output enable
reg            cfg_wpo;  // write protect output
reg            cfg_coe;  // clock output enable
reg            cfg_bit;  // bit mode
reg            cfg_dir;  // shift direction (0 - lsb first, 1 - msb first)
reg            cfg_pol;  // clock polarity
reg            cfg_pha;  // clock phase

////////////////////////////////////////////////////////////////////////////////
// configuration registers                                                    //
////////////////////////////////////////////////////////////////////////////////

// SPI configuration (read access)
assign reg_cfg = {16'h0000,                     4'h0,
                  cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo,
                  cfg_coe,                      3'h0,
                  cfg_bit, cfg_dir, cfg_pol, cfg_pha};

// SPI configuration (write access)
always @(posedge clk, posedge rst)
if (rst) begin
  {cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo} <= CFG_RST [11: 8];
  {cfg_coe}                            <= CFG_RST [ 7   ];
  {cfg_bit, cfg_dir, cfg_pol, cfg_pha} <= CFG_RST [ 3: 0];
end else if (reg_wen & (reg_adr == 2'd0) & ~reg_wrq) begin
  {cfg_hle, cfg_wpe, cfg_hlo, cfg_wpo} <= reg_wdt [11: 8];
  {cfg_coe}                            <= reg_wdt [ 7   ];
  {cfg_bit, cfg_dir, cfg_pol, cfg_pha} <= reg_wdt [ 3: 0];
end

reg [31:0] xip_reg;

// XIP configuration
always @(posedge clk, posedge rst)
if (rst) begin
  xip_reg <= XIP_RST [31: 0];
end else if (reg_wen & (reg_adr == 2'd1) & ~reg_wrq) begin
  xip_reg <= reg_wdt;
end

////////////////////////////////////////////////////////////////////////////////
// data register                                                              //
////////////////////////////////////////////////////////////////////////////////

wire        cmo_trn;
wire        cmi_trn;

reg [31:0] cmd_wdt;
reg [31:0] cmd_rdt;

// output data
always @(posedge clk)
if (reg_wen & (reg_adr == 2'd1) & ~reg_wrq)  cmd_wdt <= reg_wdt;

assign cmo_trn = cmo_req & cmo_grt;
assign cmi_trn = cmi_req & cmi_grt;

// input data
always @(posedge clk)
if (cmi_trn)  cmd_rdt <= cmi_dat;

////////////////////////////////////////////////////////////////////////////////
// control register                                                           //
////////////////////////////////////////////////////////////////////////////////

// command output
assign cmo_req = 1'b0;
assign cmo_dat = 1'b0;
assign cmo_ctl = 1'b0;
// command input
assign cmi_req = 1'b0;

endmodule
