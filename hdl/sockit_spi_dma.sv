////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  DMA (direct memory access) interface                                      //
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
  // bus properties
  parameter ENDIAN = "BIG",  // endian options include "BIG", "LITTLE"
  // port widths
  parameter DW     =    32   // command data width
)(
  // AMBA AXI4
  axi4_if.m              axi,
  // data streams
  sockit_spi_if.s        sdw,  // stream data write
  sockit_spi_if.d        sdr   // stream data read
);

////////////////////////////////////////////////////////////////////////////////
// data write channel                                                         //
////////////////////////////////////////////////////////////////////////////////

// burst counter
logic [8-1:0] cnt;

////////////////////////////////////////////////////////////////////////////////
// data write channel                                                         //
////////////////////////////////////////////////////////////////////////////////

// write address options affect write response
always_ff @ (posedge axi.ACLK)
if (axi.AWVALID & axi.AWREADY) begin
  // store transfer ID
  axi.WID <= axi.AWID;
  // AXI4 write response depends on whether a supported request was made
  axi.WRESP <= (axi.WRSIZE <= axi4_pkg::int2SIZE(DW)) ? axi4_pkg::OKAY
                                                      : axi4_pkg::SLVERR;
end

// wait for both address and data bus to be valid before declaring ready
// also wait for previous write response to complete
assign axi.AWREADY = axi.AWVALID & axi.WVALID & ~axi.BVALID;
//TODO: next version might offer better performance, but it can also cause
//combinatorial loops and long timing paths
//assign axi.AWREADY = axi.AWVALID & axi.WVALID & (~axi.BVALID | axi.BREADY);

// generate write response after confirming write address transfer
always_ff @ (posedge axi.ACLK, negedge axi.ARESETn)
if (~axi.ARESETn) begin
  axi.BVALID <= 1'b0;
end else begin
  if (axi.AWREADY) begin
    axi.BVALID <= 1'b1;
  end else if (axi.BVALID & axi.BREADY) begin
    axi.BVALID <= 1'b0;
  end
end

// stream data write
assign sdw.vld = axi.WVALID;
assign sdw.dat = axi.WDATA ;
assign axi.WREADY = sdw.rdy;

////////////////////////////////////////////////////////////////////////////////
// data read channel                                                          //
////////////////////////////////////////////////////////////////////////////////

// read address options affect read data
always_ff @ (posedge axi.ACLK)
if (axi.ARVALID & axi.ARREADY) begin
  // store transfer ID
  axi.RID <= axi.ARID;
  // AXI4 read response depends on whether a supported request was made
  axi.RRESP <= (axi.ARSIZE <= axi4_pkg::int2SIZE(DW)) ? axi4_pkg::OKAY
                                                      : axi4_pkg::SLVERR;
end

// store transfer size 
always_ff @ (posedge axi.ACLK, negedge axi.ARESETn)
if (~axi.ARESETn) begin
  cnt <= 0;
end else begin
  if (axi.ARVALID & axi.ARREADY) begin
    cnt <= axi4_pkg::SIZE2int(axi.ARSIZE) - 1;
  end else if (axi.RVALID & axi.RREADY) begin
    cnt <= cnt - 1;
  end
end

// return active LAST at the end of the burst
always_ff @ (posedge axi.ACLK)
if (axi.ARVALID & axi.ARREADY) begin
  axi.RLAST <= ~|cnt;
end

// stream data read
assign axi.RVALID = sdr.vld;
assign axi.RDATA  = sdr.dat;
assign sdr.rdy = axi.RREADY;

endmodule: sockit_spi_dma
