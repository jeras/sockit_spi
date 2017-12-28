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
// the valid signal (tsk_vld) and the data drain confirms the transfer by     //
// setting the ready signal (tsk_rdy).                                        //
//                                                                            //
//                       ----------   vld    ----------                       //
//                       )      S | ------>  | D      (                       //
//                       (      R |          | R      )                       //
//                       )      C | <------  | N      (                       //
//                       ----------   rdy    ----------                       //
//                                                                            //
// DMA task protocol:                                                         //
//                                                                            //
// The protocol uses a control (tsk_ctl) and a status (tsk_sts) signal. The   //
// control signal uses handshaking while the status signal does not. The      //
// control signal is a command from REG to DMA to start a DMA sequence.       //
//                                                                            //
// Control signal fields:                                                     //
// [31   ] - iod - command input/output direction (0 - input, 1 - output)     //
// [30: 0] - len - DMA sequence length in Bytes                               //
//                                                                            //
// The status signal is primarily used to control the command arbiter. While  //
// a DMA sequence is processing the DMA should have exclusive access to the   //
// command bus. The status signal is also connected to REG, so that the CPU   //
// can poll DMA status and interrupts can be generated.                       //
//                                                                            //
// Status signal fields:                                                      //
// [30: 0] - ost - DMA sequence counter status                                //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi_dma #(
  // bus properties
  parameter ENDIAN  =        "BIG",  // endian options include "BIG", "LITTLE"
  // port widths
  parameter DAW     =           32,  // DMA address width
  parameter CCO     =          5+7,  // command control output width
  parameter CCI     =            4,  // command control  input width
  parameter CDW     =           32   // command data width
)(
  // system signals
  input  logic           clk,      // clock
  input  logic           rst,      // reset
  // memory bus interface
  output logic           dma_wen,  // write enable
  output logic           dma_ren,  // read enable
  output logic [DAW-1:0] dma_adr,  // address
  output logic     [3:0] dma_ben,  // byte enable
  output logic    [31:0] dma_wdt,  // write data
  input  logic    [31:0] dma_rdt,  // read data
  input  logic           dma_wrq,  // wait request
  input  logic           dma_err,  // error response
  // configuration
  input  logic    [31:0] spi_cfg,  // DMA configuration
  input  logic    [31:0] adr_rof,  // address read  offset
  input  logic    [31:0] adr_wof,  // address write offset
  // DMA task interface
  input  logic           tsk_vld,  // valid
  input  logic    [31:0] tsk_ctl,  // control
  output logic    [31:0] tsk_sts,  // status
  output logic           tsk_rdy,  // ready
  // arbiter locks
  output logic           arb_lko,  // command output lock
  output logic           arb_lki,  // command input  lock
  // command output
  output logic           cmo_vld,  // valid
  output logic [CCO-1:0] cmo_ctl,  // control
  output logic [CDW-1:0] cmo_dat,  // data
  input  logic           cmo_rdy,  // ready
  // command input
  input  logic           cmi_vld,  // valid
  input  logic [CCI-1:0] cmi_ctl,  // control
  input  logic [CDW-1:0] cmi_dat,  // data
  output logic           cmi_rdy   // ready
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// DMA counter width
localparam DCW = (DAW>31) ? 31 : DAW;

// configuration
logic           cfg_end;  // bus endianness (0 - little, 1 - big)
logic           cfg_prf;  // read prefetch (0 - single, 1 - double)
logic     [1:0] cfg_bts;  // bus transfer size (n+1 Bytes)
logic           cfg_m_s;  // SPI bus mode (0 - slave, 1 - master)
logic           cfg_pkm;  // packaging mode
logic     [1:0] cfg_iom;  // SPI data IO mode

// DMA task interface
logic           tsk_trn;  // transfer

// memory interface
logic           dma_trn;  // bus transfer
logic           dma_rdy;  // bus ready for new transfer
logic    [31:0] dma_rdr;  // read data register
logic     [1:0] dma_rdb;  // read data byte
logic           dma_rds;  // read data status

// cycle registers
logic           cyc_run;  // cycle run-status
logic           cyc_iod;  // cycle input/output direction
logic           cyc_oen;  // command output enable
logic           cyc_ien;  // command input  enable
logic [DCW-1:0] cyc_ocn;  // command output counter
logic [DCW-1:0] cyc_icn;  // command input  counter
logic           cyc_ofn;  // command output finish
logic           cyc_ifn;  // command input  finish

// command output
logic           cmo_trn;  // transfer

// command input
logic           cmi_trn;  // transfer

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

// bus transfer
assign dma_trn = (~dma_wrq | dma_err) & (dma_wen | dma_ren);

// bus ready
assign dma_rdy = ~(dma_wen | dma_ren) | dma_trn;

// bus cycle TODO remove
//assign dma_wcy = cyc_ien &  cmi_vld;
//assign dma_rcy = cyc_oen & ~(cyc_ofn & cmo_trn) & (cmo_rdy | ~dma_rds & ~dma_ren);

// write/read control (write has priority over read)
always_ff @ (posedge clk, posedge rst)
if (rst) begin
  dma_wen <= 1'b0;
  dma_ren <= 1'b0;
end else if (dma_rdy) begin
  dma_wen <= cyc_ien & cmi_vld;
  dma_ren <= cyc_oen & ~cyc_iod;
end

// write/read address register
always_ff @ (posedge clk)
if      (tsk_trn)  dma_adr <= tsk_ctl[31] ? adr_rof : adr_wof;
else if (dma_trn)  dma_adr <= dma_adr + (cfg_bts + 'd1);

// write byte enable
always_ff @ (posedge clk)
if (tsk_trn) begin
  if (~tsk_ctl[31]) begin
    case (cfg_bts)
      2'd0    : dma_ben <= (ENDIAN == "BIG") ? 4'b1000 : 4'b0001;
      2'd1    : dma_ben <= (ENDIAN == "BIG") ? 4'b1100 : 4'b0011;
      2'd2    : dma_ben <= 4'b1111;
      default : dma_ben <= 4'b1111;
    endcase
  end else      dma_ben <= 4'b1111;
end else if (dma_trn) begin
  if (~cyc_iod) begin
    case (cfg_bts)
      2'd0    : dma_ben <= (ENDIAN == "BIG") ? {dma_ben[0:0], dma_ben[3:1]} : {dma_ben[2:0], dma_ben[3:3]};
      2'd1    : dma_ben <= (ENDIAN == "BIG") ? {dma_ben[1:0], dma_ben[3:2]} : {dma_ben[1:0], dma_ben[3:2]};
      2'd2    : dma_ben <= 4'b1111;
      default : dma_ben <= 4'b1111;
    endcase
  end
end

// write data
// TODO proper alignment
always_ff @ (posedge clk)
if (cmi_trn) begin
  case (cfg_bts)
    // TODO, the address is not always correct
    2'd0    : dma_wdt <= (ENDIAN == "BIG") ? cmi_dat[ 7:0] << 8*(2'd3-dma_adr[1:0]) : cmi_dat[ 7:0] << 8*dma_adr[1:0];
    2'd1    : dma_wdt <= (ENDIAN == "BIG") ? cmi_dat[15:0] << 8*(2'd3-dma_adr[1:0]) : cmi_dat[15:0] << 8*dma_adr[1:0];
    2'd2    : dma_wdt <= cmi_dat;
    default : dma_wdt <= cmi_dat;
  endcase
end

// read data register, byte
always_ff @ (posedge clk)
if (dma_ren & dma_trn) begin
  dma_rdr <= dma_rdt;
  dma_rdb <= dma_adr [1:0];
end

// read data status
always_ff @ (posedge clk, posedge rst)
if (rst)                  dma_rds <= 1'b0;
else begin
  if (dma_ren & dma_trn)  dma_rds <= 1'b1;
  else if      (cmo_trn)  dma_rds <= 1'b0;
end

////////////////////////////////////////////////////////////////////////////////
// cycle control                                                              //
////////////////////////////////////////////////////////////////////////////////

// control registers
always_ff @ (posedge clk, posedge rst)
if (rst) begin
  cyc_run <= 1'b0;
  cyc_iod <= 1'b0;
  cyc_oen <= 1'b0;
  cyc_ien <= 1'b0;
end else begin
  if (tsk_trn) begin
    cyc_run <=  1'b1;
    cyc_iod <=  tsk_ctl[31];
    cyc_oen <=  1'b1;
    cyc_ien <= ~tsk_ctl[31];
  end else begin
    if (cyc_iod) begin
      if (cmo_trn)  cyc_run <= ~cyc_ofn;
      if (cmi_trn)  cyc_run <= ~cyc_ifn;
    end
    if (cmo_trn)  cyc_oen <= ~cyc_ofn;
    if (cmi_trn)  cyc_ien <= ~cyc_ifn;
  end
end

// transfer counter
always_ff @ (posedge clk, posedge rst)
if (rst) begin
  cyc_ocn <= 'd0;
  cyc_icn <= 'd0;
end else if (cfg_m_s) begin
  // master operation
  if (tsk_trn) begin
    cyc_ocn <= tsk_ctl[DCW-1:0];
    cyc_icn <= tsk_ctl[DCW-1:0];
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
// task cycle status                                                          //
////////////////////////////////////////////////////////////////////////////////

assign tsk_trn = tsk_vld & tsk_rdy;

assign tsk_sts = {cyc_run, {31-DCW{1'b0}}, cyc_iod ? cyc_ocn : cyc_icn};

assign tsk_rdy = ~cyc_run;

////////////////////////////////////////////////////////////////////////////////
// arbiter locks                                                              //
////////////////////////////////////////////////////////////////////////////////

// TODO implement real registers, with proper timing
always_comb
begin
  arb_lko = cyc_run | ~cfg_m_s;
  arb_lki = cyc_run | ~cfg_m_s;
end

////////////////////////////////////////////////////////////////////////////////
// command output                                                             //
////////////////////////////////////////////////////////////////////////////////

// transfer
assign cmo_trn = cmo_vld & cmo_rdy;

// transfer valid
assign cmo_vld = cyc_oen; //  dma_rds;

// packaging mode
assign cfg_pkm = 0;

// control            siz...siz,     pkm,     iom,     die,     doe,  sso,  cke
assign cmo_ctl = {cfg_bts, 3'd7, cfg_pkm, cfg_iom, cyc_ien, cyc_oen, 1'b1, 1'b1};

// data
generate if (ENDIAN == "BIG") begin

always_comb begin
  case (cfg_bts)
    2'd0    : cmo_dat = (dma_rdr << (8*dma_rdb)) ^ 32'h00xxxxxx;
    2'd1    : cmo_dat = (dma_rdr << (8*dma_rdb)) ^ 32'h0000xxxx;
    2'd2    : cmo_dat = (dma_rdr << (8*dma_rdb)) ^ 32'h000000xx;
    default : cmo_dat =  dma_rdr;
  endcase
end

end else if (ENDIAN == "LITTLE") begin

// TODO, think about it and than implement it
always_comb begin
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
assign cmi_trn = cmi_vld & cmi_rdy;

// transfer ready
assign cmi_rdy = dma_rdy;

endmodule: sockit_spi_dma
