////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  XIP (execute in place) engine                                             //
//                                                                            //
//  Copyright (C) 2008  Iztok Jeras                                           //
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

module sockit_spi_xip #(
  parameter XAW = 24,                // bus address width
  parameter NOP = 32'h00000000       // no operation instruction (returned on error)
)(
  // system signals
  input  wire           clk,         // clock
  input  wire           rst,         // reset
  // input bus (XIP requests)
  input  wire           bsi_wen,     // write enable
  input  wire           bsi_ren,     // read enable
  input  wire [XAW-1:0] bsi_adr,     // address
  input  wire    [31:0] bsi_wdt,     // write data
  output wire    [31:0] bsi_rdt,     // read data
  output wire           bsi_wrq,     // wait request
  // output bus (interface to SPI master registers)
  output wire           bso_wen,     // write enable
  output wire           bso_ren,     // read enable
  output wire     [1:0] bso_adr,     // address
  output wire    [31:0] bso_wdt,     // write data
  input  wire    [31:0] bso_rdt,     // read data
  input  wire           bso_wrq,     // wait request
  // configuration
  input  wire [XAW-1:8] xip_adr,     // address offset
  // status
  input  wire [XAW-1:8] xip_err      // error interrupt
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// address adder
reg  [XAW-1:0] adr_reg;  // input address register
wire [XAW-1:0] adr_sum;  // input address + offset address



endmodule
