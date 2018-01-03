////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  CDC (clock domain crossing) general purpose FIFO with gray counter        //
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

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Handshaking protocol:                                                      //
//                                                                            //
// Both the input and the output port employ the same handshaking mechanism.  //
// The data source sets the valid signal (*.vld) and the data drain           //
// confirms the transfer by setting the ready signal (*.rdy).                 //
//                                                                            //
//                       ----------   vld    ----------                       //
//                       )      S | ------>  | D      (                       //
//                       (      R |          | R      )                       //
//                       )      C | <------  | N      (                       //
//                       ----------   rdy    ----------                       //
//                                                                            //
// Clear signal:                                                              //
//                                                                            //
// The *.clr signal provides an optional synchronous clear of data counters.  //
// To be precise by applying clear the counter of the applied side copies the //
// counter value from the opposite side, thus causing the data still stored   //
// inside the FIFO to be thrown out.                                          //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi_cdc #(
  int unsigned CW = 1,  // counter width
  type         DT = logic [8-1:0]     // data type
)(
  sockit_spi_if.d cdi,  // input port
  sockit_spi_if.s cdo   // output port
);

////////////////////////////////////////////////////////////////////////////////
// gray code related functions
////////////////////////////////////////////////////////////////////////////////

// conversion from integer to gray
function automatic [CW-1:0] int2gry (input [CW-1:0] val);                                                                                                               
  integer i;
begin
  for (i=0; i<CW-1; i=i+1)  int2gry[i] = val[i+1] ^ val[i];
  int2gry[CW-1] = val[CW-1];
end
endfunction

// conversion from gray to integer
function automatic [CW-1:0] gry2int (input [CW-1:0] val);
  integer i;
begin
  gry2int[CW-1] = val[CW-1];
  for (i=CW-1; i>0; i=i-1)  gry2int[i-1] = val[i-1] ^ gry2int[i];
end
endfunction

// gray increment (with conversion into integer and back to gray)
function automatic [CW-1:0] gry_inc (input [CW-1:0] gry_cnt); 
begin
  gry_inc = int2gry (gry2int (gry_cnt) + 'd1);
end
endfunction

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// input port
logic          cdi_trn;  // transfer
logic [CW-1:0] cdi_syn;  // synchronization
logic [CW-1:0] cdi_cnt;  // gray counter
logic [CW-1:0] cdi_inc;  // gray increment

// CDC FIFO memory
DT             cdc_mem [0:2**CW-1];

// output port
logic          cdo_trn;  // transfer
logic [CW-1:0] cdo_syn;  // synchronization
logic [CW-1:0] cdo_cnt;  // gray counter
logic [CW-1:0] cdo_inc;  // gray increment

////////////////////////////////////////////////////////////////////////////////
// input port                                                                 //
////////////////////////////////////////////////////////////////////////////////

// transfer
assign cdi_trn = cdi.vld & cdi.rdy;

// counter increment
assign cdi_inc = gry_inc (cdi_cnt);

// synchronization and counter registers
always_ff @ (posedge cdi.clk, posedge cdi.rst)
if (cdi.rst) begin
                     cdi_syn <= {CW{1'b0}};
                     cdi_cnt <= {CW{1'b0}};
                     cdi.rdy <=     1'b1  ;
end else begin
                     cdi_syn <= cdo_cnt;
  if      (cdi.clr)  cdi_cnt <= cdi_syn;
  else if (cdi_trn)  cdi_cnt <= cdi_inc;
                     cdi.rdy <= cdi.rdy & ~cdi_trn | (cdi_syn != cdi.rdy ? cdi_inc : cdi_cnt);
end

// data memory
always_ff @ (posedge cdi.clk)
if (cdi_trn) cdc_mem [cdi_cnt] <= cdi.dat;

////////////////////////////////////////////////////////////////////////////////
// output port                                                                //
////////////////////////////////////////////////////////////////////////////////

// transfer
assign cdo_trn = cdo.vld & cdo.rdy;

// counter increment
assign cdo_inc = gry_inc (cdo_cnt);

// synchronization and counter registers
always_ff @ (posedge cdo.clk, posedge cdo.rst)
if (cdo.rst) begin
                     cdo_syn <= {CW{1'b0}};
                     cdo_cnt <= {CW{1'b0}};
                     cdo.vld <=     1'b0  ;
end else begin
                     cdo_syn <= cdi_cnt;
  if      (cdo.clr)  cdo_cnt <= cdo_syn;
  else if (cdo_trn)  cdo_cnt <= cdo_inc;
                     cdo.vld <= cdo.vld & ~cdo_trn | (cdo_syn != cdo.vld ? cdo_inc : cdo_cnt);
end

// asynchronous output data
assign cdo.dat = cdc_mem [cdo_cnt];

endmodule: sockit_spi_cdc
