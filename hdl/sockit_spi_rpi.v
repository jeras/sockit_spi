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

module sockit_spi_rpi #(
  // port widths
  parameter SSW     =            8,  // serial data register width
  parameter SDW     =            8,  // serial data register width
  parameter SDL     =            3,  // serial data register width logarithm
  parameter CCO     =  4+SSW+1+5+2,  // command control output width
  parameter CCI     =            1,  // command control  input width
  parameter CDW     =           32,  // command data width
  parameter BCO     =  7+SSW+1+SDL,  // buffer control output width
  parameter BCI     =            2,  // buffer control  input width
  parameter BDW     =        4*SDW   // buffer data width
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // command
  output wire           cmd_req,  // request
  input  wire [CCI-1:0] cmd_ctl,  // control
  input  wire [CDW-1:0] cmd_dat,  // data
  input  wire           cmd_grt,  // grant
  // buffer
  output wire           buf_req,  // request
  input  wire [BCI-1:0] buf_ctl,  // control
  input  wire [BDW-1:0] buf_dat,  // data
  input  wire           buf_grt   // grant
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

reg            cyc_new;

reg     [31:0] cyc_run;
reg     [31:0] cyc_len;
reg     [31:0] cyc_dat;

wire           cmd_trn;
wire           buf_trn;

////////////////////////////////////////////////////////////////////////////////
// repackaging function                                                       //
////////////////////////////////////////////////////////////////////////////////

function [4*SDW-1:0] rpk (
  input  [4*SDW-1:0] dat,
  input        [1:0] mod
);
  integer i;
begin
  for (i=0; i<SDW; i=i+1) begin
    case (mod)
      2'd0 : begin  // 3-wire
        rpk [32-1-1*i] = dat [1*SDW-1-i];
      end
      2'd1 : begin  // spi
        rpk [32-1-1*i] = dat [2*SDW-1-i];
      end
      2'd2 : begin  // dual
        rpk [32-1-2*i] = dat [4*SDW-1-i];
        rpk [32-2-2*i] = dat [3*SDW-1-i];
      end
      2'd3 : begin  // quad
        rpk [32-1-4*i] = dat [4*SDW-1-i];
        rpk [32-2-4*i] = dat [3*SDW-1-i];
        rpk [32-3-4*i] = dat [2*SDW-1-i];
        rpk [32-4-4*i] = dat [1*SDW-1-i];
      end
    endcase
  end
end
endfunction

assign cmd_trn = cmd_req & cmd_grt;
assign buf_trn = buf_req & buf_grt;

endmodule
