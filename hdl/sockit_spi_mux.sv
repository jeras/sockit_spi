////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  generic handshaking interface, stream multiplexer                         //
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

module sockit_spi_mux #(
  // data type
  parameter type DT = logic [32-1:0]
)(
  // select
  input  logic    sel,
  // input streams
  sockit_spi_if.d si0,
  sockit_spi_if.d si1,
  // output stream
  sockit_spi_if.d sto
);

// forward signals
assign sto.vld = sel ? si1.vld : si0.vld;
assign sto.dat = sel ? si1.dat : si0.dat;

// backpressure signals
assign si0.rdy = ~sel & sto.rdy;
assign si1.rdy =  sel & sto.rdy;

endmodule: sockit_spi_mux
