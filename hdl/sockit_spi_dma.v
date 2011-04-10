////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  DMA (direct memory access)                                                //
//                                                                            //
//  Copyright (C) 2011  Iztok Jeras                                           //
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

module sockit_spi_dma #(
  parameter DAW = 32   // DMA address width
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // bus interface
  input  wire           reg_wen,     // write enable
  input  wire           reg_ren,     // read enable
  input  wire     [1:0] reg_adr,     // address
  input  wire    [31:0] reg_wdt,     // write data
  output wire    [31:0] reg_rdt,     // read data
  output wire           reg_wrq,     // wait request
  output wire           reg_irq,     // interrupt request
  // configuration
  // command output
  output wire           cmo_req,     // request
  output wire    [31:0] cmo_dat,     // data
  output wire    [16:0] cmo_ctl,     // control
  input  wire           cmo_grt,     // grant
  // command input
  output wire           cmi_req,     // request
  input  wire    [31:0] cmi_dat,     // data
  input  wire     [0:0] cmi_ctl,     // control
  input  wire           cmi_grt      // grant
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////



endmodule
