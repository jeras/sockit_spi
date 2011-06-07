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
  // control/status
  input  wire           ctl_stb,  // DMA strobe
  output wire    [20:0] ctl_ctl,  // DMA control
  input  wire    [20:0] ctl_sts,  // DMA status
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

// control registers
reg      [1:0] ctl_siz;  // transfer size
reg            ctl_wen;  // write enable
reg            ctl_ren;  // read  enable
reg            ctl_pri;  // write/read priority

// DMA cycle
reg     [15:0] cyc_cnt;  // transfer counter
reg            cyc_w_r;  // write/read cycle

// control registers
always @ (posedge clk, posedge rst)
if (rst) begin
  ctl_siz <= 2'd0;
  ctl_wen <= 1'b0;
  ctl_ren <= 1'b0;
  ctl_pri <= 1'b0;
end else if (ctl_stb) begin
  ctl_siz <= ctl_ctl[17:16];
  ctl_wen <= ctl_ctl[18];
  ctl_ren <= ctl_ctl[19];
  ctl_pri <= ctl_ctl[20];
end

// address register
always @ (posedge clk)
dma_adr <= (cyc_w_r ? adr_wof : adr_rof) + {16'h0000, cyc_cnt};

// transfer counter
always @ (posedge clk)
if (cfg_m_s) begin
  // master operation
  if      (ctl_stb)  cyc_cnt <= ctl_ctl[15:0];
  else if (dma_trn)  cyc_cnt <= cyc_cnt - {14'd0, ctl_siz};
end else begin
  // slave operation
end

endmodule
