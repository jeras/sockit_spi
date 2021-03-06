////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  repackaging input data (queue protocol into command protocol)             //
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

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Handshaking protocol:                                                      //
//                                                                            //
// Both the command and the queue protocol employ the same handshaking mech-  //
// anism. The data source sets the valid signal (*_vld) and the data drain    //
// confirms the transfer by setting the ready signal (*_rdy).                 //
//                                                                            //
//                       ----------   vld    ----------                       //
//                       )      S | ------>  | D      (                       //
//                       (      R |          | R      )                       //
//                       )      C | <------  | N      (                       //
//                       ----------   rdy    ----------                       //
//                                                                            //
// Command protocol:                                                          //
//                                                                            //
// The command protocol packet transfer contains CDW=32 data bits (same as    //
// the CPU system bus) and CCI=4 control bits. Control word fields:           //
// [ 3: 0] -     - this fields have the same meaning as in the queue protocol //
//                                                                            //
// Queue protocol:                                                            //
//                                                                            //
// The queue protocol packet transfer contains QDW=4*SDW=4*8 data bits (num-  //
// ber of SPI data bits times serializer length) and QCI=4 control bits.      //
// Control word fields:                                                       //
// [    3] - new - new (first) data on input (used in slave mode)             //
// [    2] - lst - last tran. segment (used to size the input side packet)    //
// [ 1: 0] - iom - SPI data IO mode (0 - 3-wire)                              //
//               -                  (1 - SPI   )                              //
//               -                  (2 - dual  )                              //
//               -                  (3 - quad  )                              //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi_rpi #(
  // port widths
  parameter SDW     =            8,  // serial data register width
  parameter SDL     =  $clog2(SDW),  // serial data register width logarithm
  parameter CCI     =            4,  // command control input width
  parameter CDW     =           32,  // command data width
  parameter QCI     =            4,  // queue control input width
  parameter QDW     =        4*SDW   // queue data width
)(
  // system signals
  input  logic           clk,      // clock
  input  logic           rst,      // reset
  // command
  output logic           cmd_vld,  // valid
  output logic [CCI-1:0] cmd_ctl,  // control
  output logic [CDW-1:0] cmd_dat,  // data
  input  logic           cmd_rdy,  // ready
  // queue
  input  logic           que_vld,  // valid
  input  logic [QCI-1:0] que_ctl,  // control
  input  logic [QDW-1:0] que_dat,  // data
  output logic           que_rdy   // ready
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

logic           cyc_lst;
logic           cyc_new;
logic     [1:0] cyc_cnt;

logic    [31:0] rpk_dat;
logic    [31:0] cyc_dat;

logic           cmd_trn;
logic           que_trn;

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
      2'd1 : begin  // SPI
        rpk [32-1-1*i] = dat [2*SDW-1-i];
      end
      2'd2 : begin  // dual
        rpk [32-1-2*i] = dat [2*SDW-1-i];
        rpk [32-2-2*i] = dat [1*SDW-1-i];
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

////////////////////////////////////////////////////////////////////////////////
// repackaging state machine                                                  //
////////////////////////////////////////////////////////////////////////////////

// command flow control
assign cmd_vld = cyc_lst;
assign cmd_trn = cmd_vld & cmd_rdy;

// control registers
always_ff @(posedge clk, posedge rst)
if (rst) begin
  cyc_lst <= 1'b0;
  cyc_new <= 1'b0;
  cyc_cnt <= 2'd0;
end else begin
  if (que_trn) begin
    cyc_lst <= que_ctl [2];
    cyc_new <= que_ctl [3];
  end else if (cmd_trn) begin
    cyc_lst <= 1'b0;
    cyc_cnt <= 2'd0;  // TODO
  end
end

// repackaged data
assign rpk_dat = rpk(que_dat, que_ctl [1:0]);

// data registers
always_ff @(posedge clk)
if (que_trn) begin
  case (que_ctl [1:0])
    2'd0 : cyc_dat <= {cyc_dat [23: 0], rpk_dat [31:24]};
    2'd1 : cyc_dat <= {cyc_dat [23: 0], rpk_dat [31:24]};
    2'd2 : cyc_dat <= {cyc_dat [15: 0], rpk_dat [31:16]};
    2'd3 : cyc_dat <= {                 rpk_dat [31: 0]};
  endcase
end

// command control, data
assign cmd_ctl = {cyc_new, cyc_lst, cyc_cnt};
assign cmd_dat = cyc_dat;

// queue flow control
assign que_rdy = ~cyc_lst;
assign que_trn = que_vld & que_rdy;

endmodule: sockit_spi_rpi
