////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
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
  parameter SSW = 8,  // slave select width
  parameter SDW = 8   // serial data register width
)(
  // system signals
  input  wire           clk,         // clock
  input  wire           rst,         // reset
  // output buffer
  input  wire           bfo_req,
  input  wire [BOW-1:0] bfo_dat,
  input  wire    [16:0] bfo_ctl,
  output wire           bfo_grt,
  // input buffer
  output wire [BIW-1:0] bfi_wdt,
  output wire     [0:0] bfi_ctl,
  output wire           bfi_req,
  output wire           bfi_grt,

  // serial clock
  input  wire           spi_sclk_i,  // input (clock loopback)
  output wire           spi_sclk_o,  // output
  output wire           spi_sclk_e,  // output enable
  // serial input output SIO[3:0] or {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  input  wire     [3:0] spi_sio_i,   // input
  output wire     [3:0] spi_sio_o,   // output
  output wire     [3:0] spi_sio_e,   // output enable
  // active low slave select signal
  input  wire [SSW-1:0] spi_ss_i,    // input  (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_o,    // output (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_e     // output enable
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

reg      [2:0] spi_cnt;  // clock counter
reg            spi_cke;  // clock enable

reg            spi_sie;
reg      [3:0] spi_soe;
reg            spi_sce;
reg            spi_sco;
reg  [SSW-1:0] spi_sse;
reg  [SSW-1:0] spi_sso;

reg  [SDW-1:0] spi_sdo [0:3];
wire [SDW-1:0] spi_dto_3;
wire [SDW-1:0] spi_dto_2;
wire [SDW-1:0] spi_dto_1;
wire [SDW-1:0] spi_dto_0;

reg  [SDW-1:0] spi_sdi [0:3];
wire [SDW-1:0] spi_dti_3;
wire [SDW-1:0] spi_dti_2;
wire [SDW-1:0] spi_dti_1;
wire [SDW-1:0] spi_dti_0;

wire           spi_new;

////////////////////////////////////////////////////////////////////////////////
// spi cycle timing                                                           //
////////////////////////////////////////////////////////////////////////////////

// flow control for data output
assign bfo_reg = ~|spi_cnt;
assign bfo_ren = bfo_rer & bfo_reg;

// flow control for data input
assign bfi_weg = spi_sie & spi_cke & ~|spi_cnt;
assign bfi_wen = bfi_wer & bfi_weg;

// transfer length counter
always @(posedge clk_spi, posedge rst_spi)
if (rst_spi) begin
  spi_cke <= 1'b0;
  spi_cnt <= 3'd0;
end else begin
  if (bfo_ren) begin
    spi_cke <= bfo_dat [4*SDW-1+0+:1];
    spi_cnt <= bfo_dat [4*SDW-1+1+:3];
  end else begin
    if (bfo_reg)  spi_cke <= 1'b0;
    if (spi_cke)  spi_cnt <= spi_cnt - 3'd1;
  end
end

// IO control registers
always @(posedge clk_spi, posedge rst_spi)
if (rst_spi) begin
  spi_sie <=      1'b0;
  spi_soe <=      4'h0;
  spi_sce <=      1'b0;
  spi_sco <=      1'b0;
  spi_sse <= {SSW{1'b0}};
  spi_sso <= {SSW{1'b0}};
end else if (bfo_ren) begin
  spi_sie <=      bfo_dat [4*SDW-1+  4 +:1];
  spi_soe <=      bfo_dat [4*SDW-1+  5 +:4];
  spi_sce <=      bfo_dat [4*SDW-1+  9 +:1];
  spi_sco <=      bfo_dat [4*SDW-1+ 10 +:1];
  spi_sse <= {SSW{bfo_dat [4*SDW-1+ 11 +:1]}};
  spi_sso <=      bfo_dat [4*SDW-1+ 12 +:SSW];
end

assign spi_dto_3 = bfo_dat [SDW*3+:SDW];
assign spi_dto_2 = bfo_dat [SDW*2+:SDW];
assign spi_dto_1 = bfo_dat [SDW*1+:SDW];
assign spi_dto_0 = bfo_dat [SDW*0+:SDW];

assign bfi_dat = {spi_new,
                  spi_dti_3,
                  spi_dti_2,
                  spi_dti_1,
                  spi_dti_0};

////////////////////////////////////////////////////////////////////////////////
// slave select, clock, data (input, output, enable)                          //
////////////////////////////////////////////////////////////////////////////////

// serial clock input
assign spi_cli =  spi_sclk_i ^ (cfg_pol ^ cfg_pha);  // clock for input registers
assign spi_clo = ~spi_sclk_i ^ (cfg_pol ^ cfg_pha);  // clock for output registers

// serial clock output
assign spi_sclk_o = cfg_pol ^ ~(~spi_cke | clk_spi);
assign spi_sclk_e = cfg_coe;


// slave select input
assign spi_rsi = spi_ss_i;  // reset for output registers

// slave select output, output enable
assign spi_ss_o = spi_sso;
assign spi_ss_e = spi_sse;


// data input
always @ (posedge spi_cli)
begin
  spi_sdi [3] <= spi_dti_3;
  spi_sdi [2] <= spi_dti_2;
  spi_sdi [1] <= spi_dti_1;
  spi_sdi [0] <= spi_dti_0;
end

assign spi_dti_3 = {spi_sdi [3], spi_ss_i [3]};
assign spi_dti_2 = {spi_sdi [2], spi_ss_i [2]};
assign spi_dti_1 = {spi_sdi [1], spi_ss_i [1]};
assign spi_dti_0 = {spi_sdi [0], spi_ss_i [0]};

// data output
always @ (posedge spi_clo)
if (bfo_ren) begin
  spi_sdo [3] <=  spi_dto_3;
  spi_sdo [2] <=  spi_dto_2;
  spi_sdo [1] <=  spi_dto_1;
  spi_sdo [0] <=  spi_dto_0;
end else begin
  spi_sdo [3] <= {spi_sdo [3] [SDW-1:0], 1'bx};
  spi_sdo [2] <= {spi_sdo [2] [SDW-1:0], 1'bx};
  spi_sdo [1] <= {spi_sdo [1] [SDW-1:0], 1'bx};
  spi_sdo [0] <= {spi_sdo [0] [SDW-1:0], 1'bx};
end

assign spi_sio_o [3] = spi_sdo [3] [SDW-1];
assign spi_sio_o [2] = spi_sdo [2] [SDW-1];
assign spi_sio_o [1] = spi_sdo [1] [SDW-1];
assign spi_sio_o [0] = spi_sdo [0] [SDW-1];

// data output enable
assign spi_sio_e = spi_soe;

endmodule
