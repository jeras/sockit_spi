////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  CDC (clock domain crossing) general purpose gray counter                  //
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

module sockit_spi_cdc #(
  parameter CDW = 1
)(
  // input port
  input  wire  cdi_clk,  // clock
  input  wire  cdi_rst,  // reset
  input  wire  cdi_req,  // request
  output reg   cdi_grt,  // grant
  // output port
  input  wire  cdo_clk,  // clock
  input  wire  cdo_rst,  // reset
  input  wire  cdo_grt,  // grant
  output reg   cdo_req   // request
);

// gray function
function automatic [CDW-1:0] gry_inc (input [CDW-1:0] gry_cnt); 
begin
  gry_inc = gry_cnt + 'd1;
end
endfunction

// input port
reg  [CDW-1:0] cdi_syn;  // synchronization
reg  [CDW-1:0] cdi_cnt;  // gray counter
wire [CDW-1:0] cdi_inc;  // gray increment

// output port
reg  [CDW-1:0] cdo_syn;  // synchronization
reg  [CDW-1:0] cdo_cnt;  // gray counter
wire [CDW-1:0] cdo_inc;  // gray increment

////////////////////////////////////////////////////////////////////////////////
// port A
////////////////////////////////////////////////////////////////////////////////

assign cdi_inc = (cdi_req & cdi_grt) ? gry_inc (cdi_cnt) : cdi_cnt;

always @ (posedge cdi_clk, posedge cdi_rst)
if (cdi_rst) begin
  cdi_syn <= {CDW{1'b0}};
  cdi_cnt <= {CDW{1'b0}};
  cdi_grt <=      1'b0  ;
end else begin
  cdi_syn <= cdo_cnt;
  cdi_cnt <= cdi_inc;
  cdi_grt <= cdi_syn != gry_inc (cdi_inc);
end

////////////////////////////////////////////////////////////////////////////////
// port A
////////////////////////////////////////////////////////////////////////////////

assign cdo_inc = (cdo_grt & cdo_req) ? gry_inc (cdo_cnt) : cdo_cnt;

always @ (posedge cdo_clk, posedge cdo_rst)
if (cdo_rst) begin
  cdo_syn <= {CDW{1'b0}};
  cdo_cnt <= {CDW{1'b0}};
  cdo_req <=      1'b0  ;
end else begin
  cdo_syn <= cdi_cnt;
  cdo_cnt <= cdo_inc;
  cdo_req <= cdo_syn != cdo_inc;
end


endmodule
