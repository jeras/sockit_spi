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
  // port widths
  parameter SDW     =            8,  // serial data register width
  parameter SDL     =            3,  // serial data register width logarithm
  parameter CCO     =          5+6,  // command control output width
  parameter CCI     =            3,  // command control  input width
  parameter CDW     =           32,  // command data width
  parameter BCO     =        SDL+7,  // buffer control output width
  parameter BCI     =            4,  // buffer control  input width
  parameter BDW     =        4*SDW   // buffer data width
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // command
  input  wire           cmd_req,  // request
  input  wire [CCO-1:0] cmd_ctl,  // control
  input  wire [CDW-1:0] cmd_dat,  // data
  output wire           cmd_grt,  // grant
  // buffer
  output wire           buf_req,  // request
  output wire [BCO-1:0] buf_ctl,  // control
  output wire [BDW-1:0] buf_dat,  // data
  input  wire           buf_grt   // grant
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

wire           cmd_trn;  // command transfer

reg            cyc_run;  // counter run state
reg      [4:0] cyc_cnt;  // counter

reg  [CCO-6:0] cyc_ctl;  // contol register
reg  [CDW-1:0] cyc_dat;  // data   register

wire           cyc_len;  // SPI transfer length
wire           cyc_iom;  // SPI IO mode

wire           buf_trn;  // buffer transfer

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

// command flow control
assign cmd_grt = ~cyc_run;
assign cmd_trn = cmd_req & cmd_grt;

// counter
always @(posedge clk, posedge rst)
if (rst) begin
  cyc_run <= 1'b0;
  cyc_cnt <= 5'd0;
end else begin
  if (cmd_trn) begin
    cyc_run <= 1'b1;
    cyc_cnt <= cmd_ctl [CCO-6+:5];
  end else if (buf_trn) begin
    cyc_run <= cyc_cnt > SDW;
    cyc_cnt <= cyc_cnt - cyc_len;
  end
end

// SPI transfer length TODO
assign cyc_len = 3'd7;

// SPI IO mode
assign cyc_iom = cyc_ctl [5:4];

// control and data registers
always @(posedge clk)
if (cmd_trn) begin
  cyc_ctl <= cmd_ctl [CCO-6:0];
  cyc_dat <= cmd_dat;
end else if (buf_trn) begin
  cyc_dat <= cyc_dat << SDW;
end

// buffer control and data
assign buf_ctl =     {cyc_len, cyc_ctl};
assign buf_dat = rpk (cyc_dat, cyc_iom);

// buffer flow control
assign buf_req = cyc_run;
assign buf_trn = buf_req & buf_grt;

endmodule
