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

localparam SDW = 8;

// internal clocks, resets
logic           spi_clk;
logic           spi_rst;

// SPI register clocks
logic           spi_cko;  // MOSI registers
logic           spi_cki;  // MISO registers

// cycle control
sockit_spi_pkg::cmd_t cyc;
logic           cyc_end;  // cycle end

// output data signals
logic [4-1:0][SDW-1:0] spi_sdo;

// input data signals
logic [4-1:0][SDW-1:0] spi_sdi;
logic [4-1:0][SDW-1:0] spi_dti;

////////////////////////////////////////////////////////////////////////////////
// clock & reset                                                              //
////////////////////////////////////////////////////////////////////////////////

assign spi_clk = scw.clk;
assign spi_rst = scw.rst;

// register clocks
assign spi_cko =  spi_clk;  // MOSI registers
assign spi_cki = ~spi_clk;  // MISO registers

////////////////////////////////////////////////////////////////////////////////
// SPI cycle timing                                                           //
////////////////////////////////////////////////////////////////////////////////

// flow control for queue output
assign scw.rdy = cyc_end;
assign sdw.rdy = cyc_end;

// flow control for queue input
assign sdr.vld = cyc.die & cyc.cke & cyc_end;

// transfer length counter
always @(posedge spi_cko, posedge spi_rst)
if (spi_rst)          cyc.cnt <= '0;
else begin
  if       (scw.trn)  cyc.cnt <= scw.dat.cnt;
  else if (~cyc_end)  cyc.cnt <= cyc.cnt - 'd1;
end

assign cyc_end = ~|cyc.cnt;

// clock enable
always @(posedge spi_cko, posedge spi_rst)
if (spi_rst)         cyc.cke <= 1'b0;
else begin
  if      (scw.trn)  cyc.cke <= scw.dat.cke;
  else if (scw.rdy)  cyc.cke <= 1'b0;
end

// IO control registers
always @(posedge spi_cko, posedge spi_rst)
if (spi_rst) begin
  cyc.sso <= {SSW{1'b0}};
  cyc.die <=      1'b0  ;
  cyc.iom <=      2'd1  ;
end else if (scw.trn) begin
  cyc.sso <= {SSW{scw.dat.sso}} & cfg.sss;
  cyc.die <= scw.dat.die;
  cyc.iom <= scw.dat.iom;
end

assign sdr.dat = spi_dti;

////////////////////////////////////////////////////////////////////////////////
// slave select, clock, data (input, output, enable)                          //
////////////////////////////////////////////////////////////////////////////////

// serial clock output
assign spi.clk_o = cfg.pol ^ (cyc.cke & ~(spi_clk ^ cfg.pha));
assign spi.clk_e = cfg.coe;


// slave select output, output enable
assign spi.ssn_o =      cyc.sso  ;
assign spi.ssn_e = {SSW{cfg.soe}};

// shift register
always @ (posedge spi_cko)
if (sdw.trn) begin
  spi_sdo <= sdw.dat;
end else begin
  // TODO: recode shift register
  case (scw.dat.iom)
    2'd0 : spi_sdo <= spi_sdo[32-1-:1];
    2'd1 : spi_sdo <= spi_sdo[32-1-:1];
    2'd2 : spi_sdo <= spi_sdo[32-1-:1];
    2'd3 : spi_sdo <= spi_sdo[32-1-:1];
  endcase
end

assign spi.sio_o = spi_sdo[32-1-:4];

// data output enable
always @(posedge spi_cko, posedge spi_rst)
if (spi_rst) begin
  spi.sio_e <= 4'h0;
end else if (scw.trn) begin
  case (scw.dat.iom)
    2'd0 : spi.sio_e <= {4{scw.dat.doe}} & 4'b0001;
    2'd1 : spi.sio_e <= {4{scw.dat.doe}} & 4'b0001;
    2'd2 : spi.sio_e <= {4{scw.dat.doe}} & 4'b0011;
    2'd3 : spi.sio_e <= {4{scw.dat.doe}} & 4'b1111;
  endcase
end

endmodule: sockit_spi_ser
