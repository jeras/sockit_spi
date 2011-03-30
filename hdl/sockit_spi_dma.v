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
  parameter DW = 1'b1   // 
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // CPU side bus
  input  wire           bsc_wen,  // write enable
  input  wire           bsc_ren,  // read enable
  input  wire    [31:0] bsc_wdt,  // write data
  output wire    [31:0] bsc_rdt,  // read data
  input  wire           bsc_ful,  // full
  input  wire           bsc_emp,  // empty
  // SPI side bus
  output wire           bss_wen,  // write enable
  output wire           bss_ren,  // read enable
  output wire    [31:0] bss_wdt,  // write data
  input  wire    [31:0] bss_rdt,  // read data
  input  wire           bss_ful,  // full
  input  wire           bss_emp   // empty
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// memory


endmodule
