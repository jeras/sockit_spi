////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  memory mapped configuration, control and status registers                 //
//                                                                            //
//  Copyright (C) 2008-2011  Iztok Jeras                                      //
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
//  Address space                                                             //
//                                                                            //
//  adr | reg name, short description                                         //
// -----+-------------------------------------------------------------------- //
//  0x0 | cfg - SPI configuration/parameterization                            //
//  0x1 | ctl - SPI control/status                                            //
//  0x2 | irq - SPI interrupts                                                //
//  0x3 | off - AXI address offset                                            //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi_reg #(
  // configuration/parameterization register parameters
  sockit_spi_pkg::cfg_t RST = 32'h00000000,  // reset value
  sockit_spi_pkg::cfg_t MSK = 32'hffffffff,  // implementation mask
  // XIP parameters
  int unsigned XAW =         24,  // XIP address width
  int unsigned OFF = 24'h000000   // address write offset
)(
  // AMBA AXI4-Lite
  axi4_lite_if.s         axi,
  // SPI/XIP/DMA configuration
  output sockit_spi_pkg::cfg_t  cfg,  // configuration register
  // address offsets
  output logic [XAW-1:0] off,  // AXI address offset
  // command stream
  sockit_spi_if.s        scw   // command
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

logic    [31:0] spi_sts;  // SPI status
logic    [31:0] reg_irq;  //

////////////////////////////////////////////////////////////////////////////////
// read access                                                                //
////////////////////////////////////////////////////////////////////////////////

// read address channel is never delayed
always_ff @(posedge axi.ACLK, negedge axi.ARESETn)
if (~axi.ARESETn) begin
  axi.ARREADY = 1'b0;
end else begin
  axi.ARREADY = 1'b1;
end

// read data
always_ff @(posedge axi.ACLK)
case (axi.ARADDR[2+:2])
  2'd0: axi.RDATA <= cfg;
  2'd1: axi.RDATA <= spi_sts;
  2'd2: axi.RDATA <= reg_irq;
  2'd3: axi.RDATA <= off;
endcase

// read data channel is never delayed
always_ff @(posedge axi.ACLK, negedge axi.ARESETn)
if (~axi.ARESETn) begin
  axi.RREADY = 1'b0;
end else begin // TODO condition
  axi.RREADY = 1'b1;
end

////////////////////////////////////////////////////////////////////////////////
// configuration registers                                                    //
////////////////////////////////////////////////////////////////////////////////

// XIP/DMA address offsets
always_ff @(posedge axi.ACLK, negedge axi.ARESETn)
if (~axi.ARESETn) begin
  cfg <= RST;
  off <= OFF;
end else if (axi.WVALID & axi.WREADY) begin
  case (axi.AWADDR[2+:2])
    2'd0: cfg <= axi.WDATA & MSK | RST & ~MSK;
    2'd3: off <= axi.WDATA[XAW-1:0];
  endcase
end

////////////////////////////////////////////////////////////////////////////////
// interrupts                                                                 //
////////////////////////////////////////////////////////////////////////////////

// interrupt
assign reg_irq = 1'b0; // TODO

////////////////////////////////////////////////////////////////////////////////
// command command                                                            //
////////////////////////////////////////////////////////////////////////////////

// command output
assign scw.vld = axi.WVALID;
assign scw.dat = axi.WDATA ;
assign axi.WREADY = scw.rdy;

endmodule: sockit_spi_reg
