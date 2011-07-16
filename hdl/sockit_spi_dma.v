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

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Handshaking protocol:                                                      //
//                                                                            //
// The DMA task protocol employ a handshaking mechanism. The data source sets //
// the request signal (tsk_req) and the data drain confirms the transfer by   //
// setting the grant signal (tsk_grt).                                        //
//                                                                            //
//                       ----------   req    ----------                       //
//                       )      S | ------>  | D      (                       //
//                       (      R |          | R      )                       //
//                       )      C | <------  | N      (                       //
//                       ----------   grt    ----------                       //
//                                                                            //
// DMA task protocol:                                                         //
//                                                                            //
// The protocol uses a control (tsk_ctl) and a status (tsk_sts) signal. The   //
// control signal uses handshaking while the status signal does not. The      //
// control signal is a command from REG to DMA to start a DMA sequence.       //
//                                                                            //
// Control signal fields:                                                     //
// [31   ] - ien - command input  data enable                                 //
// [   30] - oen - command output data enable                                 //
// [15: 0] - len - DMA sequence length in Bytes                               //
//                                                                            //
// The status signal is primarily used to control the command arbiter. While  //
// a DMA sequence is processing the DMA should have exclusive access to the   //
// command bus. The status signal is also connected to REG, so that the CPU   //
// can poll DMA status and interrupts can be generated.                       //
//                                                                            //
// Status signal fields:                                                      //
// [1] - ist - command input  status                                          //
// [0] - ost - command output status                                          //
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
  output wire [DAW-1:0] dma_adr,  // address
  output wire     [3:0] dma_ben,  // byte enable
  output reg     [31:0] dma_wdt,  // write data
  input  wire    [31:0] dma_rdt,  // read data
  input  wire           dma_wrq,  // wait request
  input  wire           dma_err,  // error response
  // configuration
  input  wire    [31:0] spi_cfg,  // DMA configuration
  input  wire    [31:0] adr_rof,  // address read  offset
  input  wire    [31:0] adr_wof,  // address write offset
  // DMA task interface
  input  wire           tsk_req,  // request
  input  wire    [31:0] tsk_ctl,  // control
  output wire     [1:0] tsk_sts,  // status
  output wire           tsk_grt,  // grant
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

// DMA counter width
localparam DCW = (DAW>30) ? 30 : DAW;

// configuration
wire           cfg_end;  // bus endianness (0 - little, 1 - big)
wire           cfg_prf;  // read prefetch (0 - single, 1 - double)
wire     [1:0] cfg_bts;  // bus transfer size (n+1 Bytes)
wire           cfg_m_s;  // SPI bus mode (0 - slave, 1 - master)
wire     [1:0] cfg_iom;  // SPI data IO mode

// DMA task interface
wire           tsk_trn;  // transfer

// memory interface
wire           dma_wtr, dma_rtr;  // write/read transfer
wire           dma_wrd, dma_rrd;  // write/read ready
wire           dma_wcy, dma_rcy;  // write/read cycle
reg  [DAW-1:0] dma_wad, dma_rad;  // write/read address
wire [DAW-1:0] dma_wai, dma_rai;  // write/read address increment
reg      [3:0] dma_wbe;           // write byte enable
reg     [31:0] dma_rdr;           // read data register
reg      [1:0] dma_rdb;           // read data byte
reg            dma_rds;           // read data status

// cycle registers
reg            cyc_run;           // run cycle
reg            cyc_oen, cyc_ien;  // output/input enable
reg  [DCW-1:0] cyc_ocn, cyc_icn;  // output/input counter
wire           cyc_ofn, cyc_ifn;  // output/input finish

// command output
wire           cmo_trn;  // transfer

// command input
wire           cmi_trn;  // transfer

////////////////////////////////////////////////////////////////////////////////
// configuration                                                              //
////////////////////////////////////////////////////////////////////////////////

assign cfg_end = spi_cfg[   16];
assign cfg_prf = spi_cfg[   10];
assign cfg_bts = spi_cfg[ 9: 8];
assign cfg_m_s = spi_cfg[    7];
assign cfg_iom = spi_cfg[ 5: 4];

////////////////////////////////////////////////////////////////////////////////
// memory interface                                                           //
////////////////////////////////////////////////////////////////////////////////

// write/read transfers
assign dma_wtr = (~dma_wrq | dma_err) & dma_wen;
assign dma_rtr = (~dma_wrq | dma_err) & dma_ren;

// write/read ready
assign dma_wrd = (~dma_wen | dma_wtr);
assign dma_rrd = (~dma_ren | dma_rtr);

// write/read cycle
assign dma_wcy = cyc_ien &  cmi_req;
assign dma_rcy = cyc_oen & ~(cyc_ofn & cmo_trn) & (cmo_grt | ~dma_rds & ~dma_ren);

// write/read control (write has priority over read)
always @ (posedge clk, posedge rst)
if (rst) begin
  dma_wen <= 1'b0;
  dma_ren <= 1'b0;
end else begin
  if (dma_wrd)  dma_wen <= dma_wcy;
  if (dma_rrd)  dma_ren <= dma_rcy & ~dma_wcy;
end

// write/read address register
always @ (posedge clk)
if (tsk_trn) begin
  dma_wad <= adr_wof;
  dma_rad <= adr_rof;
end else begin
  if (dma_wtr)  dma_wad <= dma_wai;
  if (dma_rtr)  dma_rad <= dma_rai;
end

// write/read address increment
assign dma_wai = dma_wad + (cfg_bts + 'd1);
assign dma_rai = dma_rad + (cfg_bts + 'd1);

// write/read address multiplexer
assign dma_adr = dma_wen ? dma_wad : dma_rad;

// write byte enable
always @ (posedge clk)
if (tsk_trn) begin
  case (cfg_bts)
    2'd0    : dma_wbe <= (ENDIAN == "BIG") ? 4'b1000 : 4'b0001;
    2'd1    : dma_wbe <= (ENDIAN == "BIG") ? 4'b1100 : 4'b0011;
    2'd2    : dma_wbe <= 4'b1111;
    default : dma_wbe <= 4'b1111;
  endcase
end else if (dma_wtr) begin
  case (cfg_bts)
    2'd0    : dma_wbe <= (ENDIAN == "BIG") ? {dma_wbe[0:0], dma_wbe[3:1]} : {dma_wbe[2:0], dma_wbe[3:3]};
    2'd1    : dma_wbe <= (ENDIAN == "BIG") ? {dma_wbe[1:0], dma_wbe[3:2]} : {dma_wbe[1:0], dma_wbe[3:2]};
    2'd2    : dma_wbe <= 4'b1111;
    default : dma_wbe <= 4'b1111;
  endcase
end

// transfer size multiplexer
assign dma_ben = dma_wen ? dma_wbe : 4'hf;

// write data
// TODO proper alignment
always @ (posedge clk)
if (cmi_trn) begin
  case (cfg_bts)
    // TODO, the address is not always correct
    2'd0    : dma_wdt <= (ENDIAN == "BIG") ? cmi_dat[ 7:0] << 8*(2'd3-dma_wad[1:0]) : cmi_dat[ 7:0] << 8*dma_wad[1:0];
    2'd1    : dma_wdt <= (ENDIAN == "BIG") ? cmi_dat[15:0] << 8*(2'd3-dma_wad[1:0]) : cmi_dat[15:0] << 8*dma_wad[1:0];
    2'd2    : dma_wdt <= cmi_dat;
    default : dma_wdt <= cmi_dat;
  endcase
end

// read data register, byte
always @ (posedge clk)
if (dma_rtr) begin
  dma_rdr <= dma_rdt;
  dma_rdb <= dma_rad [1:0];
end

// read data status
always @ (posedge clk, posedge rst)
if (rst)             dma_rds <= 1'b0;
else begin
  if      (dma_rtr)  dma_rds <= 1'b1;
  else if (cmo_trn)  dma_rds <= 1'b0;
end

////////////////////////////////////////////////////////////////////////////////
// cycle control                                                              //
////////////////////////////////////////////////////////////////////////////////

// control registers
always @ (posedge clk, posedge rst)
if (rst) begin
  cyc_run <= 1'b0;
  cyc_oen <= 1'b0;
  cyc_ien <= 1'b0;
end else begin
  if (tsk_trn) begin
    cyc_run <= |tsk_ctl[31:30];
    cyc_oen <=  tsk_ctl[   30];
    cyc_ien <=  tsk_ctl[31   ];
  end else begin
    if (cmo_trn)  cyc_run <= ~cyc_ofn;
    if (cmo_trn)  cyc_oen <= ~cyc_ofn & cyc_oen;
    if (cmi_trn)  cyc_ien <= ~cyc_ifn;
  end
end

// transfer counter
always @ (posedge clk, posedge rst)
if (rst) begin
  cyc_ocn <= 'd0;
  cyc_icn <= 'd0;
end else if (cfg_m_s) begin
  // master operation
  if (tsk_trn) begin
    if (|tsk_ctl[31:30])  cyc_ocn <= tsk_ctl[DCW-1:0];
    if ( tsk_ctl[31   ])  cyc_icn <= tsk_ctl[DCW-1:0];
  end else begin
    if (cmo_trn)  cyc_ocn <= cyc_ocn - (cfg_bts + 'd1);
    if (cmi_trn)  cyc_icn <= cyc_icn - (cfg_bts + 'd1);
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

assign tsk_trn = tsk_req & tsk_grt;

assign tsk_sts = {cyc_ien, cyc_run};

assign tsk_grt = 1'b1;

////////////////////////////////////////////////////////////////////////////////
// command output                                                             //
////////////////////////////////////////////////////////////////////////////////

// transfer
assign cmo_trn = cmo_req & cmo_grt;

// transfer request
assign cmo_req = cyc_run & (~cyc_oen | dma_rds);

// control            siz...siz,     iom,     die,     doe,  sso,  cke
assign cmo_ctl = {cfg_bts, 3'd7, cfg_iom, cyc_ien, cyc_oen, 1'b1, 1'b1};

// data
generate if (ENDIAN == "BIG") begin

always @ (*) begin
  case (cfg_bts)
    2'd0    : cmo_dat = (dma_rdr << (8*dma_rdb)) ^ 32'h00xxxxxx;
    2'd1    : cmo_dat = (dma_rdr << (8*dma_rdb)) ^ 32'h0000xxxx;
    2'd2    : cmo_dat = (dma_rdr << (8*dma_rdb)) ^ 32'h000000xx;
    default : cmo_dat =  dma_rdr;
  endcase
end

end else if (ENDIAN == "LITTLE") begin

// TODO, think about it and than implement it
always @ (*) begin
  case (cfg_bts)
    2'd0    : cmo_dat = (dma_rdr << (8*dma_rdb)) ^ 32'h00xxxxxx;
    2'd1    : cmo_dat = (dma_rdr << (8*dma_rdb)) ^ 32'h0000xxxx;
    2'd2    : cmo_dat = (dma_rdr << (8*dma_rdb)) ^ 32'h000000xx;
    default : cmo_dat =  dma_rdr;
  endcase
end

end endgenerate

////////////////////////////////////////////////////////////////////////////////
// command input                                                              //
////////////////////////////////////////////////////////////////////////////////

// transfer
assign cmi_trn = cmi_req & cmi_grt;

// transfer grant
assign cmi_grt = dma_wrd;

endmodule
