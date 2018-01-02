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
  int unsigned SSW = sockit_spi_pkg::SSW  // slave select width
)(
  // SPI configuration
  input  sockit_spi_pkg::cfg_t cfg,  // SPI/XIP/DMA configuration
  // command/data streams
  sockit_spi_if.d        scw,   // command
  sockit_spi_if.d        sdw,   // data write
  sockit_spi_if.s        sdr,   // data read
  // SPI interface
  spi_if.m               spi
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// internal clocks, resets
logic           spi_clk;
logic           spi_rst;

// SPI register clocks
logic           spi_cko;  // MOSI registers
logic           spi_cki;  // MISO registers

// bit counter
// TODO: parameterize counter size
logic  [14-1:0] cnt;  // counter
logic           lst;  // last bit

// serial data IO data
logic   [4-1:0] spi_sdo;  // serial data output
logic   [4-1:0] spi_sdi;  // serial data input

// shift register
logic  [32-1:0] spi_sro;  // shift register output
logic  [32-1:0] spi_sri;  // shift register input

////////////////////////////////////////////////////////////////////////////////
// clock & reset                                                              //
////////////////////////////////////////////////////////////////////////////////

assign spi_clk = scw.clk;
assign spi_rst = scw.rst;

// register clocks
assign spi_cko =  spi_clk;  // MOSI registers
assign spi_cki = ~spi_clk;  // MISO registers

////////////////////////////////////////////////////////////////////////////////
// read stream
////////////////////////////////////////////////////////////////////////////////

assign sdr.dat = spi_sri;

////////////////////////////////////////////////////////////////////////////////
// write stream
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// SPI cycle timing                                                           //
////////////////////////////////////////////////////////////////////////////////

// flow control for queue output
assign scw.rdy = lst;
assign sdw.rdy = lst;

// flow control for queue input
assign sdr.vld = scw.dat.die & scw.dat.cke & lst;

// transfer length counter
always @(posedge spi_clk, posedge spi_rst)
if (spi_rst)         cnt <= '0;
else begin
  if      (scw.trn)  cnt <= scw.dat.cnt;
  else if (~lst)     cnt <= cnt - 'd1;
end

assign lst = ~|cnt;

////////////////////////////////////////////////////////////////////////////////
// slave select, clock, data (input, output, enable)                          //
////////////////////////////////////////////////////////////////////////////////

// serial clock output
assign spi.clk_o = cfg.pol ^ (scw.dat.cke & ~(spi_clk ^ cfg.pha));
assign spi.clk_e = cfg.coe;


// slave select output, output enable
assign spi.ssn_o = {SSW{scw.dat.sso}} & cfg.sss;
assign spi.ssn_e = {SSW{    cfg.soe}};


// serial data input (register)
always @(posedge spi_cki, posedge spi_rst)
if (spi_rst) begin
  spi_sdi <= 4'h0;
end else begin
  if (scw.trn) begin
    case (scw.dat.iom)
      // TODO: check how this is implemented on FPGA, feedback or clock enable
      2'd0 : spi_sdi <= spi.sio_i & 4'b0001;
      2'd1 : spi_sdi <= spi.sio_i & 4'b0001;
      2'd2 : spi_sdi <= spi.sio_i & 4'b0011;
      2'd3 : spi_sdi <= spi.sio_i & 4'b1111;
    endcase
  end
end


// shift register input
always_comb
case (scw.dat.iom)
  2'd0 : spi_sri <= {spi_sro[32-1:0], spi_sdi[1-1:0]};
  2'd1 : spi_sri <= {spi_sro[32-1:0], spi_sdi[1-1:0]};
  2'd2 : spi_sri <= {spi_sro[32-2:0], spi_sdi[2-1:0]};
  2'd3 : spi_sri <= {spi_sro[32-4:0], spi_sdi[4-1:0]};
endcase

// shift register
always @ (posedge spi_cko, posedge spi_rst)
if (spi_rst) begin
  spi_sro <= '0;
end else begin
  if (sdw.trn) begin
    spi_sro <= sdw.dat;
  end else begin
    spi_sro <= spi_sri;
  end
end


// serial data output
always @(posedge spi_cko, posedge spi_rst)
if (spi_rst) begin
  spi.sio_e <= 4'h0;
end else if (scw.trn) begin
  case (scw.dat.iom)
    // TODO: for hold_n and wp_n a different approach might be better
    2'd0 : spi.sio_o <= spi_sro[32-1-1+:1] & 4'b0001;
    2'd1 : spi.sio_o <= spi_sro[32-1-1+:1] & 4'b0001;
    2'd2 : spi.sio_o <= spi_sro[32-2-1+:2] & 4'b0011;
    2'd3 : spi.sio_o <= spi_sro[32-4-1+:4] & 4'b1111;
  endcase
end

// data output enable
always @(posedge spi_cko, posedge spi_rst)
if (spi_rst) begin
  spi.sio_e <= 4'h0;
end else if (scw.trn) begin
  case (scw.dat.iom)
    // TODO: for hold_n and wp_n a different approach might be better
    2'd0 : spi.sio_e <= {4{scw.dat.doe}} & 4'b0001;
    2'd1 : spi.sio_e <= {4{scw.dat.doe}} & 4'b0001;
    2'd2 : spi.sio_e <= {4{scw.dat.doe}} & 4'b0011;
    2'd3 : spi.sio_e <= {4{scw.dat.doe}} & 4'b1111;
  endcase
end

endmodule: sockit_spi_ser
