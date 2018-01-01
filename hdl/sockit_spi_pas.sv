////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  generic handshaking interface, stream pass through                        //
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

module sockit_spi_pas #(
  // data type
  parameter type DT = logic [32-1:0]
)(
  // input stream
  sockit_spi_if.d sti,
  // output stream
  sockit_spi_if.d sto
);

// forward signals
assign sto.vld = sti.vld;
assign sto.dat = sti.dat;

// backpressure signals
assign sti.rdy = sto.rdy;

endmodule: sockit_spi_pas
