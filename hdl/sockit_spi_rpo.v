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

module sockit_spi_rpo #(
  parameter SSW =     8,  // serial data register width
  parameter SDW =     8,  // serial data register width
  parameter BDW = 4*SDW   // buffer data register width
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // command
  output wire           cmd_req,  // request
  output wire    [31:0] cmd_dat,  // data
  output wire    [16:0] cmd_ctl,  // control
  input  wire           cmd_grt,  // grant
  // buffer
  output wire           buf_req,  // request
  output wire [BDW-1:0] buf_dat,  // data
  output wire    [16:0] buf_ctl,  // control
  input  wire           buf_grt   // grant
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

wire           cmd_trn;

reg     [31:0] cyc_dat;

reg            cyc_run;

reg      [4:0] cyc_len;
reg            cyc_sco;
reg            cyc_sce;
reg            cyc_sie;
reg            cyc_soe;
reg            cyc_iom; // IO mode
reg  [SSW-1:0] cyc_sso;
reg            cyc_sse;

wire           buf_trn;

////////////////////////////////////////////////////////////////////////////////
// repackaging function                                                       //
////////////////////////////////////////////////////////////////////////////////

// output data repackegind 
function [4*SDW-1:0] rpk (
  input  [4*SDW-1:0] dat,
  input        [1:0] mod
);
  integer i;
begin
  for (i=0; i<SDW; i=i+1) begin
    case (mod)
      2'd0 : begin  // 3-wire
        rpk [4*SDW-1-i] = dat [32-1-1*i];
        rpk [3*SDW-1-i] = 1'b1;
        rpk [2*SDW-1-i] = 1'b1;
        rpk [1*SDW-1-i] = 1'b1;
      end
      2'd1 : begin  // spi
        rpk [4*SDW-1-i] = 1'b1;
        rpk [3*SDW-1-i] = dat [32-1-1*i];
        rpk [2*SDW-1-i] = 1'b1;
        rpk [1*SDW-1-i] = 1'b1;
      end
      2'd2 : begin  // dual
        rpk [4*SDW-1-i] = dat [32-1-2*i];
        rpk [3*SDW-1-i] = dat [32-2-2*i];
        rpk [2*SDW-1-i] = 1'b1;
        rpk [1*SDW-1-i] = 1'b1;
      end
      2'd3 : begin  // quad
        rpk [4*SDW-1-i] = dat [32-1-4*i];
        rpk [3*SDW-1-i] = dat [32-2-4*i];
        rpk [2*SDW-1-i] = dat [32-3-4*i];
        rpk [1*SDW-1-i] = dat [32-4-4*i];
      end
    endcase
  end
end
endfunction

assign cmd_grn = ~cyc_run;
assign cmd_trn = cmd_req & cmd_grt;

always @(posedge clk, posedge rst)
if (rst) begin
  cyc_run <= 1'b0;
  cyc_len <= 5'd0;
  cyc_sco <= 1'b0;
  cyc_sce <= 1'b0;
  cyc_sie <= 1'b0;
  cyc_soe <= 1'b0;
  cyc_iom <= 1'b0;
  cyc_sse <= 1'b0;
  cyc_sso <=  'b0;
end else begin
  if (cmo_trn) begin
    cyc_run <= 1'b1;
    cyc_len <= cmd_ctl [ 4:0];
    cyc_sco <= cmd_ctl [ 5];
    cyc_sce <= cmd_ctl [ 6];
    cyc_sie <= cmd_ctl [ 7];
    cyc_soe <= cmd_ctl [ 8];
    cyc_iom <= cmd_ctl [ 9];
    cyc_sse <= cmd_ctl [10];
    cyc_sso <= cmd_ctl [11+:SSW];
  end else if (buf_trn) begin
    cyc_run <= cyc_len > SDW;
    cyc_len <= cyc_len - buf_len - 1;
  end
end

always @(posedge clk)
if (cmo_trn)
  cyc_dat <= cmd_dat;
else if (bfo_trn) begin
  cyc_dat <= cyc_dat << SDW;
end      

assign buf_dat = rpk (cyc_dat);

assign buf_ctl [ 2: 0] = 3'd7;  // length // TODO
assign buf_ctl [ 3]    = cyc_sco;
assign buf_ctl [ 4]    = cyc_sce;
assign buf_ctl [ 6]    = cyc_sie;
assign buf_ctl [ 7]    = cyc_soe;
assign buf_ctl [ 8]    = cyc_iom;
assign buf_ctl [ 9]    = cyc_sse;
assign buf_ctl [10]    = cyc_sso;

assign buf_req = cyc_run;
assign buf_trn = buf_req & buf_grt;

endmodule
