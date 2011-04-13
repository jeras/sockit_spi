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
  // port widths
  parameter SSW     =            8,  // slave select width
  parameter SDW     =            8,  // serial data register width
  parameter SDL     =            3,  // serial data register width logarithm
  parameter BCO     =  7+SSW+1+SDL,  // buffer control output width
  parameter BCI     =            2,  // buffer control  input width
  parameter BDW     =        4*SDW   // buffer data width
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // configuration
  input  wire           cfp_pol,  // clock polarity
  input  wire           cfp_pha,  // clock phase
  // output buffer
  input  wire           bfo_req,  // request
  input  wire [BCO-1:0] bfo_ctl,  // control
  input  wire [BDW-1:0] bfo_dat,  // data
  output wire           bfo_grt,  // grant
  // input buffer
  output wire           bfi_req,  // request
  output wire [BCI-1:0] bfi_ctl,  // control
  output wire [BDW-1:0] bfi_dat,  // data
  input  wire           bfi_grt,  // grant

  // SCLK (serial clock)
  input  wire           spi_sclk_i,  // input (clock loopback)
  output wire           spi_sclk_o,  // output
  output wire           spi_sclk_e,  // output enable
  // SIO  (serial input output) {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  input  wire     [3:0] spi_sio_i,   // input
  output wire     [3:0] spi_sio_o,   // output
  output wire     [3:0] spi_sio_e,   // output enable
  // SS_N (slave select - active low signal)
  input  wire [SSW-1:0] spi_ss_i,    // input  (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_o,    // output (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_e     // output enable
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// buffer transfers
wire           bfi_trn;
wire           bfo_trn;

// cycle timing
reg  [SDL-1:0] cyc_cnt;  // clock counter
reg            cyc_cke;  // clock enable
wire           cyc_end;  // cycle end

// output control signals
reg  [SSW-1:0] cyc_sso;  // slave select outputs
reg  [SSW-1:0] cyc_sse;  // slave select output enable
reg      [3:0] cyc_oen;  // output enable

// input control signals
reg            cyc_ien;  // input enable
reg            cyc_lst;  // input last (signal for synchronization purposes)
reg            cyc_new;  // new (first) data on input (used in slave mode)

// output data signals
reg  [SDW-1:0] spi_sdo [0:3];
wire [SDW-1:0] spi_dto_3;
wire [SDW-1:0] spi_dto_2;
wire [SDW-1:0] spi_dto_1;
wire [SDW-1:0] spi_dto_0;

// input data signals
reg  [SDW-1:0] spi_sdi [0:3];
wire [SDW-1:0] spi_dti_3;
wire [SDW-1:0] spi_dti_2;
wire [SDW-1:0] spi_dti_1;
wire [SDW-1:0] spi_dti_0;

////////////////////////////////////////////////////////////////////////////////
// spi cycle timing                                                           //
////////////////////////////////////////////////////////////////////////////////

// flow control for buffer output
assign bfo_grt = cyc_end;
assign bfo_trn = bfo_req & bfo_grt;

// flow control for buffer input
assign bfi_req = spi_sie & cyc_cke & cyc_end;
assign bfi_trn = bfi_req & bfi_grt;

// transfer length counter
always @(posedge clk, posedge rst)
if (rst) begin
  cyc_cnt <=  'd0;
  cyc_cke <= 1'b0;
end else begin
  if (bfo_trn) begin
    cyc_cnt <= bfo_ctl [    0+:SDL];
    cyc_cke <= bfo_ctl [1+SDL+:  1];
  end else begin
    if (~cyc_end)  cyc_cnt <= cyc_cnt - 'd1;
    if ( bfo_grt)  cyc_cke <= 1'b0;
  end
end

assign cyc_end = ~|cyc_cnt;

// IO control registers
always @(posedge clk, posedge rst)
if (rst) begin
  cyc_sso <= {SSW{1'b0}};
  cyc_sse <= {SSW{1'b0}};
  cyc_oen <=      4'h0;
  cyc_ien <=      1'b0;
  cyc_lst <=      1'b0;
end else if (bfo_trn) begin
  cyc_sso <=      bfo_ctl [      1+SDL+:SSW];
  cyc_sse <= {SSW{bfo_ctl [  SSW+1+SDL+:  1]}};
  cyc_oen <=      bfo_ctl [1+SSW+1+SDL+:  4];
  cyc_ien <=      bfo_ctl [2+SSW+1+SDL+:  1];
  cyc_lst <=      bfo_ctl [3+SSW+1+SDL+:  1];
end

assign {spi_dto_3, spi_dto_2, spi_dto_1, spi_dto_0} = bfo_dat;

assign bfi_ctl = {cyc_lst, cyc_new};
assign bfi_dat = {spi_dti_3, spi_dti_2, spi_dti_1, spi_dti_0};

////////////////////////////////////////////////////////////////////////////////
// slave select, clock, data (input, output, enable)                          //
////////////////////////////////////////////////////////////////////////////////

// serial clock input
assign spi_cli =  spi_sclk_i ^ (cfg_pol ^ cfg_pha);  // clock for input registers
assign spi_clo = ~spi_sclk_i ^ (cfg_pol ^ cfg_pha);  // clock for output registers

// serial clock output
assign spi_sclk_o = cfg_pol ^ ~(~cyc_cke | clk);
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
if (bfo_trn) begin
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
