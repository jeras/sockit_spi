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
  parameter    CW = 1,   // counter width
  parameter    DW = 1    // data    width
)(
  // input port
  input  wire          cdi_clk,  // clock
  input  wire          cdi_rst,  // reset
  input  wire [DW-1:0] cdi_dat,  // data
  input  wire          cdi_req,  // request
  output reg           cdi_grt,  // grant
  // output port
  input  wire          cdo_clk,  // clock
  input  wire          cdo_rst,  // reset
  input  wire          cdo_grt,  // grant
  output reg           cdo_req,  // request
  output wire [DW-1:0] cdo_dat   // data
);

// gray function
function automatic [CW-1:0] gry_inc (input [CW-1:0] gry_cnt); 
begin
  gry_inc = gry_cnt + 'd1;
end
endfunction

// input port
wire          cdi_trn;  // transfer
reg  [CW-1:0] cdi_syn;  // synchronization
reg  [CW-1:0] cdi_cnt;  // gray counter
wire [CW-1:0] cdi_inc;  // gray increment

// CDC FIFO memory
reg  [DW-1:0] cdc_mem [0:2**CW-1];

// output port
wire          cdo_trn;  // transfer
reg  [CW-1:0] cdo_syn;  // synchronization
reg  [CW-1:0] cdo_cnt;  // gray counter
wire [CW-1:0] cdo_inc;  // gray increment

////////////////////////////////////////////////////////////////////////////////
// port A
////////////////////////////////////////////////////////////////////////////////

// transfer
assign cdi_trn = cdi_req & cdi_grt;

// counter increment
assign cdi_inc = cdi_trn ? gry_inc (cdi_cnt) : cdi_cnt;

// synchronization and counter registers
always @ (posedge cdi_clk, posedge cdi_rst)
if (cdi_rst) begin
  cdi_syn <= {CW{1'b0}};
  cdi_cnt <= {CW{1'b0}};
  cdi_grt <=     1'b1  ;
end else begin
  cdi_syn <= cdo_cnt;
  cdi_cnt <= cdi_inc;
  cdi_grt <= cdi_grt ? (cdi_trn ? cdi_syn != gry_inc (cdi_cnt) : 1'b1)
                     : (cdi_syn !=          cdi_cnt );
end

// data memory
always @ (posedge cdi_clk)
if (cdi_trn) cdc_mem [cdi_cnt] <= cdi_dat;

////////////////////////////////////////////////////////////////////////////////
// port A
////////////////////////////////////////////////////////////////////////////////

// transfer
assign cdo_trn = cdo_req & cdo_grt;

// counter increment
assign cdo_inc = cdo_trn ? gry_inc (cdo_cnt) : cdo_cnt;

// synchronization and counter registers
always @ (posedge cdo_clk, posedge cdo_rst)
if (cdo_rst) begin
  cdo_syn <= {CW{1'b0}};
  cdo_cnt <= {CW{1'b0}};
  cdo_req <=     1'b0  ;
end else begin
  cdo_syn <= cdi_cnt;
  cdo_cnt <= cdo_inc;
  cdo_req <= cdo_req ? (cdo_trn ? cdo_syn != gry_inc (cdo_cnt) : 1'b1)
                     : (cdo_syn !=          cdo_cnt );
end

// asynchronous output data
assign cdo_dat = cdc_mem [cdo_cnt];

endmodule
