////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  data serializer/de-serializer, slave selects, clocks                      //
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

module sockit_spi_ser #(
  // port widths
  int unsigned SSW     = sockit_spi_pkg::SSW,  // slave select width
  int unsigned SDW     = sockit_spi_pkg::SDW,  // serial data register width
  int unsigned SDL     = sockit_spi_pkg::SDL,  // serial data register width logarithm
  int unsigned QCO     =        SDL+7,  // queue control output width
  int unsigned QCI     =            4,  // queue control  input width
  int unsigned QDW     =        4*SDW   // queue data width
)(
  // system signals
  input  logic           clk,      // clock
  input  logic           rst,      // reset
  // SPI clocks
  output logic           spi_cko,  // output registers
  output logic           spi_cki,  // input  registers
  // SPI configuration
  input  sockit_spi_pkg::cfg_t spi_cfg,  // SPI/XIP/DMA configuration
  // control/data streams
  sockit_spi_if.d        quc,   // command queue
  sockit_spi_if.d        quo,   // output  queue
  sockit_spi_if.s        qui,   // input   queue
  // SPI interface
  spi_if.m               spi
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// internal clocks, resets
logic           spi_sclk;
logic           spi_clk;

// cycle control
sockit_spi_pkg::cmd_t cyc;
logic           cyc_end;  // cycle end

// output data signals
logic [4-1:0][SDW-1:0] spi_sdo;

// input data signals
logic [4-1:0][SDW-1:0] spi_sdi;
logic [4-1:0][SDW-1:0] spi_dti;

////////////////////////////////////////////////////////////////////////////////
// master/slave mode                                                          //
////////////////////////////////////////////////////////////////////////////////

// clock driver source
assign spi_sclk = clk ^ cfg.pha;

// clock source
assign spi_clk = cfg.m_s ? clk : spi.sclk_i ^ (cfg.pol ^ cfg.pha);

// register clocks
assign spi_cko =  spi_clk;  // output registers
assign spi_cki = ~spi_clk;  // input  registers

////////////////////////////////////////////////////////////////////////////////
// SPI cycle timing                                                           //
////////////////////////////////////////////////////////////////////////////////

// flow control for queue output
assign quc.rdy = cyc_end;
assign quo.rdy = cyc_end;

// flow control for queue input
assign qui.vld = cyc.die & cyc.cke & cyc_end;

// transfer length counter
always @(posedge spi_cko, posedge rst)
if (rst)              cyc.cnt <= {SDL{1'b0}};
else begin
  if       (quc.trn)  cyc.cnt <= quc.dat.cnt;
  else if (~cyc_end)  cyc.cnt <= cyc.cnt - 'd1;
end

assign cyc_end = ~|cyc.cnt;

// clock enable
always @(posedge spi_sclk, posedge rst)
if (rst)             cyc.cke <= 1'b0;
else begin
  if      (quc.trn)  cyc.cke <= quc.dat.cke;
  else if (quc.rdy)  cyc.cke <= 1'b0;
end

// IO control registers
always @(posedge spi_cko, posedge rst)
if (rst) begin
  cyc.sso <= {SSW{1'b0}};
  cyc.die <=      1'b0  ;
  cyc.iom <=      2'd1  ;
  cyc.lst <=      1'b0  ;
end else if (quc.trn) begin
  cyc.sso <= {SSW{quc.dat.sso}} & cfg.sss;
  cyc.die <= quc.dat.die;
  cyc.iom <= quc.dat.iom;
  cyc.lst <= quc.dat.lst;
end

assign qui.dat = spi_dti;

////////////////////////////////////////////////////////////////////////////////
// slave select, clock, data (input, output, enable)                          //
////////////////////////////////////////////////////////////////////////////////

// serial clock output
assign spi.clk_o = cfg.pol ^ (cyc.cke & ~(spi_sclk));
assign spi.clk_e = cfg.coe;


// slave select output, output enable
assign spi.ssn_o =      cyc.sso  ;
assign spi.ssn_e = {SSW{cfg.soe}};


// data output
always @ (posedge spi_cko)
if (quo.trn) begin
  spi_sdo <= quo.dat;
end else begin
  if (spi.sio_e[3])  spi_sdo[3] <= {spi_sdo[3][SDW-2:0], 1'bx};
  if (spi.sio_e[2])  spi_sdo[2] <= {spi_sdo[2][SDW-2:0], 1'bx};
  if (spi.sio_e[1])  spi_sdo[1] <= {spi_sdo[1][SDW-2:0], 1'bx};
  if (spi.sio_e[0])  spi_sdo[0] <= {spi_sdo[0][SDW-2:0], 1'bx};
end

assign spi.sio_o[3] = spi_sdo[3][SDW-1];
assign spi.sio_o[2] = spi_sdo[2][SDW-1];
assign spi.sio_o[1] = spi_sdo[1][SDW-1];
assign spi.sio_o[0] = spi_sdo[0][SDW-1];

// data output enable
always @(posedge spi_cko, posedge rst)
if (rst) begin
  spi.sio_e <= 4'h0;
end else if (quc.trn) begin
  case (quc.dat.iom)
    2'd0 : spi.sio_e <= {4{quc.dat.doe}} & 4'b0001;
    2'd1 : spi.sio_e <= {4{quc.dat.doe}} & 4'b0001;
    2'd2 : spi.sio_e <= {4{quc.dat.doe}} & 4'b0011;
    2'd3 : spi.sio_e <= {4{quc.dat.doe}} & 4'b1111;
  endcase
end


// data input
always @ (posedge spi_cki)
if (cyc.die) begin
  spi_sdi <= spi_dti;
end

assign spi_dti[3] = {spi_sdi[3][SDW-2:0], spi_sio_i[3]};
assign spi_dti[2] = {spi_sdi[2][SDW-2:0], spi_sio_i[2]};
assign spi_dti[1] = {spi_sdi[1][SDW-2:0], spi_sio_i[1]};
assign spi_dti[0] = {spi_sdi[0][SDW-2:0], spi_sio_i[0]};

endmodule
