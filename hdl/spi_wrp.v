////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) wrapper (SPI master + slave)                     //
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

`timescale 1us / 1ns

module spi_wrp #(
  parameter CTL_RST = 32'h00000000,  // control/status register reset value
  parameter CTL_MSK = 32'hffffffff,  // control/status register implementation mask
  parameter CFG_RST = 32'h00000000,  // configuration register reset value
  parameter CFG_MSK = 32'hffffffff,  // configuration register implementation mask
  parameter XIP_RST = 32'h00000000,  // XIP configuration register reset value
  parameter XIP_MSK = 32'h00000001,  // XIP configuration register implentation mask
  parameter NOP     = 32'h00000000,  // no operation instuction for the given CPU
  parameter XAW     =           24,  // XIP address width
  parameter SDW     =           32,  // shift register data width
  parameter SSW     =            8   // slave select width
)(
  // system signals (used by the CPU interface)
  input  wire           clk,         // clock
  input  wire           rst,         // reset
  input  wire           clk_spi,     // clock for SPI IO
  // XIP interface bus
  input  wire           xip_ren,     // read enable
  input  wire [XAW-1:0] xip_adr,     // address
  output wire    [31:0] xip_rdt,     // read data
  output wire           xip_wrq,     // wait request
  output wire           xip_irq,     // interrupt request
  // registers interface bus
  input  wire           reg_wen,     // write enable
  input  wire           reg_ren,     // read enable
  input  wire     [1:0] reg_adr,     // address
  input  wire    [31:0] reg_wdt,     // write data
  output wire    [31:0] reg_rdt,     // read data
  output wire           reg_wrq,     // wait request
  output wire           reg_irq      // interrupt request
);

////////////////////////////////////////////////////////////////////////////////
// local parameters and signals                                               //
////////////////////////////////////////////////////////////////////////////////

// SPI signals
wire [SSW-1:0] spi_ss_n;
wire           spi_sclk;
wire           spi_mosi;
wire           spi_miso;
wire           spi_wp_n;
wire           spi_hold_n;

// IO buffer signals
wire [SSW-1:0] spi_ss_i,
               spi_ss_o,
               spi_ss_e;
wire           spi_sclk_i,
               spi_sclk_o,
               spi_sclk_e;
wire     [3:0] spi_sio_i,
               spi_sio_o,
               spi_sio_e;

////////////////////////////////////////////////////////////////////////////////
// spi controller instance                                                    //
////////////////////////////////////////////////////////////////////////////////

sockit_spi #(
  .XAW         (XAW),
  .SSW         (SSW)
) sockit_spi (
  // system signals (used by the CPU bus interface)
  .clk         (clk),
  .rst         (rst),
  .clk_spi     (clk),
  // XIP interface
  .xip_ren     (xip_ren),
  .xip_adr     (xip_adr),
  .xip_rdt     (xip_rdt),
  .xip_wrq     (xip_wrq),
  .xip_irq     (xip_irq),
  // register interface
  .reg_wen     (reg_wen),
  .reg_ren     (reg_ren),
  .reg_adr     (reg_adr),
  .reg_wdt     (reg_wdt),
  .reg_rdt     (reg_rdt),
  .reg_wrq     (reg_wrq),
  .reg_irq     (reg_irq),
  // SPI signals (should be connected to tristate IO pads)
  // serial clock
  .spi_sclk_i  (spi_sclk_i),
  .spi_sclk_o  (spi_sclk_o),
  .spi_sclk_e  (spi_sclk_e),
  // serial input output SIO[3:0] or {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  .spi_sio_i   (spi_sio_i),
  .spi_sio_o   (spi_sio_o),
  .spi_sio_e   (spi_sio_e),
  // active low slave select signal
  .spi_ss_i    (spi_ss_i),
  .spi_ss_o    (spi_ss_o),
  .spi_ss_e    (spi_ss_e)
);

////////////////////////////////////////////////////////////////////////////////
// SPI tristate buffers                                                       //
////////////////////////////////////////////////////////////////////////////////

// clock
//bufif1 buffer_sclk (spi_sclk, spi_sclk_o, spi_sclk_e);
assign spi_sclk = spi_sclk_e ? spi_sclk_o : 1'bz;
assign spi_sclk_i = spi_sclk;

// data
//bufif1 buffer_sio [3:0] ({spi_hold_n, spi_wp_n, spi_miso, spi_mosi}, spi_sio_o, spi_sio_e);
//assign spi_sio_i =       {spi_hold_n, spi_wp_n, spi_miso, spi_mosi};
//bufif1 buffer_hold_n (spi_hold_n, spi_sio_o[3], spi_sio_e[3]);
//bufif1 buffer_wp_n   (spi_wp_n  , spi_sio_o[2], spi_sio_e[2]);
//bufif1 buffer_miso   (spi_miso  , spi_sio_o[1], spi_sio_e[1]);
//bufif1 buffer_mosi   (spi_mosi  , spi_sio_o[0], spi_sio_e[0]);
assign spi_hold_n = spi_sio_e[3] ? spi_sio_o[3] : 1'bz;
assign spi_wp_n   = spi_sio_e[2] ? spi_sio_o[2] : 1'bz;
assign spi_miso   = spi_sio_e[1] ? spi_sio_o[1] : 1'bz;
assign spi_mosi   = spi_sio_e[0] ? spi_sio_o[0] : 1'bz;
assign spi_sio_i =   {spi_hold_n, spi_wp_n, spi_miso, spi_mosi};

// slave select (active low)
//bufif1 buffer_ss_n [SSW-1:0] (spi_ss_n, ~spi_ss_o, spi_ss_e);
assign spi_ss_n[0] = spi_ss_e[0] ? ~spi_ss_o[0] : 1'bz;
assign spi_ss_i = spi_ss_n;

////////////////////////////////////////////////////////////////////////////////
// SPI slave (serial Flash)                                                   //
////////////////////////////////////////////////////////////////////////////////

// SPI slave model
spi_flash_model #(
  .DIOM      (2'd1),
  .MODE      (2'd0)
) slave_spi (
  .ss_n      (spi_ss_n[0]),
  .sclk      (spi_sclk),
  .mosi      (spi_mosi),
  .miso      (spi_miso),
  .wp_n      (spi_wp_n),
  .hold_n    (spi_hold_n)
);

endmodule
