////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  generic handshaking interface, stream fork                                //
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

module sockit_spi_frk #(
  // data type
  parameter type DT = logic [32-1:0]
)(
  // select
  input  logic    sel,
  // output streams
  sockit_spi_if.d so0,
  sockit_spi_if.d so1,
  // input stream
  sockit_spi_if.d sti
);

// forward signals
assign so0.vld = ~sel ? sti.vld : 1'b0;
assign so1.vld =  sel ? sti.vld : 1'b0;
assign so0.dat = ~sel ? sti.dat : '0;
assign so1.dat =  sel ? sti.dat : '0;

// backpressure signals
assign sti.rdy = sel ? so1.rdy : so0.rdy;

endmodule: sockit_spi_frk
