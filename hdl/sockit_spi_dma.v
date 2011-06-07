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
  // port widths
  parameter DAW     =           32,  // DMA address width
  parameter CCO     =          5+6,  // command control output width
  parameter CCI     =            4,  // command control  input width
  parameter CDW     =           32   // command data width
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // bus interface
  output reg            dma_wen,  // write enable
  output reg            dma_ren,  // read enable
  output reg  [DAW-1:0] dma_adr,  // address
  output reg      [3:0] dma_ben,  // byte enable
  output wire    [31:0] dma_wdt,  // write data
  input  wire    [31:0] dma_rdt,  // read data
  input  wire           dma_wrq,  // wait request
  input  wire           dma_err,  // error response
  // configuration
  input  wire           cfg_m_s,  // mode (0 - slave, 1 - master)
  input  wire     [7:0] cfg_dma,  // DMA configuration
  input  wire    [31:0] adr_rof,  // address read  offset
  input  wire    [31:0] adr_wof,  // address write offset
  // control
  input  wire           ctl_req,  // DMA transfer request
  output wire           ctl_grt,  // DMA transfer grant
  input  wire    [15:0] ctl_len,  // DMA transfer length
  // command output
  output wire           cmo_req,  // request
  output wire [CCO-1:0] cmo_ctl,  // control
  output wire [CDW-1:0] cmo_dat,  // data
  input  wire           cmo_grt,  // grant
  // command input
  input  wire           cmi_req,  // request
  input  wire [CCI-1:0] cmi_ctl,  // control
  input  wire [CDW-1:0] cmi_dat,  // data
  output wire           cmi_grt   // grant
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// DMA bus transfer
wire           dma_trn;

wire           ctl_wen;
reg     [15:0] ctl_cnt;
reg     [ 1:0] ctl_siz;

// address register
always @ (posedge clk)
dma_adr <= (ctl_wen ? adr_wof : adr_rof) + {16'h0000, ctl_cnt};

// transfer counter
always @ (posedge clk)
if (cfg_m_s) begin
  // master operation
  if (~|ctl_cnt & ctl_req)  ctl_cnt <= ctl_len;
  else if        (dma_trn)  ctl_cnt <= ctl_cnt - {14'd0, ctl_siz};
end else begin
  // slave operation
end

endmodule
