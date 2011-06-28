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
  // bus properties
  parameter ENDIAN  =        "BIG",  // endian options include "BIG", "LITTLE"
  // port widths
  parameter DAW     =           32,  // DMA address width
  parameter CCO     =          5+6,  // command control output width
  parameter CCI     =            4,  // command control  input width
  parameter CDW     =           32   // command data width
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // memory bus interface
  output reg            dma_wen,  // write enable
  output reg            dma_ren,  // read enable
  output reg  [DAW-1:0] dma_adr,  // address
  output reg      [3:0] dma_ben,  // byte enable
  output reg     [31:0] dma_wdt,  // write data
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
  input  wire    [20:0] ctl_ctl,  // DMA control
  output wire    [20:0] ctl_sts,  // DMA status
  // command output
  output wire           cmo_req,  // request
  output wire [CCO-1:0] cmo_ctl,  // control
  output reg  [CDW-1:0] cmo_dat,  // data
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

// memory interface
wire           dma_wen_trn;  // write transfer
wire           dma_ren_trn;  // read  transfer
wire           dma_trn;  // common transfer
wire           dma_wrd, dma_rrd;  // write/read ready
wire           dma_wcy, dma_rcy;  // write/read cycle

// cycle registers
reg      [1:0] cyc_siz;  // transfer size
reg            cyc_oen, cyc_ien;  // output/input enable
reg     [15:0] cyc_ocn, cyc_icn;  // output/input counter
wire           cyc_ofn, cyc_ifn;  // output/input finish

// command output
wire           cmo_trn;  // transfer

// command input
wire           cmi_trn;  // transfer

////////////////////////////////////////////////////////////////////////////////
// memory interface                                                           //
//////////////////////////////////////////////////////////////////////////

// write/read transfers
assign dma_wen_trn = (~dma_wrq | dma_err) & dma_wen;
assign dma_ren_trn = (~dma_wrq | dma_err) & dma_ren;
assign dma_trn     = (~dma_wrq | dma_err) & (dma_wen | dma_ren);

// write/read ready
assign dma_wrd = (~dma_wen | dma_wen_trn);
assign dma_rrd = (~dma_ren | dma_ren_trn);

// write/read cycle
assign dma_wcy = cyc_ien & cmi_req;
assign dma_rcy = cyc_oen & cmo_grt;

// write/read control (write has priority over read)
always @ (posedge clk, posedge rst)
if (rst) begin
  dma_wen <= 1'b0;
  dma_ren <= 1'b0;
end else begin
  if (dma_wrd)  dma_wen <= dma_wcy;
  if (dma_rrd)  dma_ren <= dma_rcy & ~dma_wcy;
end

// transfer size
always @ (posedge clk)
dma_ben <= 4'hf;

// address register
always @ (posedge clk)
dma_adr <= dma_wcy ? adr_wof + {16'h0000, cyc_icn}
                   : adr_rof + {16'h0000, cyc_ocn};

// write data
// TODO proper alignment
always @ (posedge clk)
if (cmi_trn)  dma_wdt <= cmi_dat;

////////////////////////////////////////////////////////////////////////////////
// cycle control                                                              //
////////////////////////////////////////////////////////////////////////////////

// control registers
always @ (posedge clk, posedge rst)
if (rst) begin
  cyc_siz <= 2'd0;
  cyc_oen <= 1'b0;
  cyc_ien <= 1'b0;
end else begin
  if (ctl_stb) begin
    cyc_siz <= ctl_ctl[17:16];
    cyc_oen <= ctl_ctl[18];
    cyc_ien <= ctl_ctl[19];
  end else begin
    if (cmo_trn) cyc_oen <= cyc_ofn;
    if (cmi_trn) cyc_ien <= cyc_ifn;
  end
end

// transfer counter
always @ (posedge clk, posedge rst)
if (rst) begin
  cyc_ocn <= 16'd0;
  cyc_icn <= 16'd0;
end else if (cfg_m_s) begin
  // master operation
  if (ctl_stb) begin
    if (ctl_ctl[18])  cyc_ocn <= ctl_ctl[15:0];
    if (ctl_ctl[19])  cyc_icn <= ctl_ctl[15:0];
  end else begin
    if (cmo_trn)  cyc_ocn <= cyc_ocn - ({14'd0, cyc_siz} + 16'd1);
    if (cmi_trn)  cyc_icn <= cyc_icn - ({14'd0, cyc_siz} + 16'd1);
  end
end else begin
  // slave operation
end

// cycle finish
assign cyc_ofn = ~|cyc_ocn;
assign cyc_ifn = ~|cyc_icn;

////////////////////////////////////////////////////////////////////////////////
// cycle status                                                               //
////////////////////////////////////////////////////////////////////////////////

assign ctl_sts = {~cyc_ifn, ~cyc_ofn};

////////////////////////////////////////////////////////////////////////////////
// command output                                                             //
////////////////////////////////////////////////////////////////////////////////

// transfer
assign cmo_trn = cmo_req & cmo_grt;

// transfer request
assign cmo_req = dma_rrd & cyc_oen;

// control                    siz,  lst,     iom,  sso,  cke
assign cmo_ctl = {cyc_siz, 3'b000, 1'b0, cfg_iom, 1'b1, 1'b1};

// data
generate if (ENDIAN == "BIG") begin

always @ (*) begin
  case (cyc_siz)
    2'd0    : cmo_dat = (dma_rdt << ( 8*dma_adr[1:0])) ^ 32'h00xxxxxx;
    2'd1    : cmo_dat = (dma_rdt << (16*dma_adr[1]  )) ^ 32'h0000xxxx;
    2'd2    : cmo_dat = (dma_rdt << ( 8*dma_adr[1:0])) ^ 32'h000000xx;
    default : cmo_dat =  dma_rdt;
  endcase
end

end else if (ENDIAN == "LITTLE") begin

// TODO, think about it and than implement it
always @ (*) begin
  case (cyc_siz)
    2'd0    : cmo_dat = (dma_rdt << ( 8*dma_adr[1:0])) ^ 32'h00xxxxxx;
    2'd1    : cmo_dat = (dma_rdt << (16*dma_adr[1]  )) ^ 32'h0000xxxx;
    2'd2    : cmo_dat = (dma_rdt << ( 8*dma_adr[1:0])) ^ 32'h000000xx;
    default : cmo_dat =  dma_rdt;
  endcase
end

end endgenerate

////////////////////////////////////////////////////////////////////////////////
// command input                                                              //
////////////////////////////////////////////////////////////////////////////////

// transfer
assign cmi_trn = cmi_req & cmi_grt;

// trasfer grant
assign cmi_grt = dma_wrd;

endmodule
