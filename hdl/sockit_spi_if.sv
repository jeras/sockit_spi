////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  generic handshaking interface                                             //
//                                                                            //
//  Copyright (C) 2008-2017  Iztok Jeras                                      //
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
// Handshaking protocol:                                                      //
//                                                                            //
// Both the command and the queue protocol employ the same handshaking mech-  //
// anism. The data source sets the valid signal (*_vld) and the data drain    //
// confirms the transfer by setting the ready signal (*_rdy).                 //
//                                                                            //
//                       ----------   vld    ----------                       //
//                       )      S | ------>  | D      (                       //
//                       (      R |          | R      )                       //
//                       )      C | <------  | N      (                       //
//                       ----------   rdy    ----------                       //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

interface sockit_spi_if #(
  parameter type DT = logic [32-1:0]  // data type
)(
  input  logic clk,  // clock
  input  logic rst,  // reset (asynchronous)
  input  logic clr   // clear (synchronous)
);

// signals
logic vld;  // valid
DT    dat;  // data
logic rdy;  // ready

logic trn;  // transfer

// transfer
assign trn = vld & rdy;

// source
modport s (
  input  clk,
  input  rst,
  input  clr,
  output vld,
  output dat,
  input  rdy
);

// drain
modport d (
  input  clk,
  input  rst,
  input  clr,
  input  vld,
  input  dat,
  output rdy
);

endinterface: sockit_spi_if
