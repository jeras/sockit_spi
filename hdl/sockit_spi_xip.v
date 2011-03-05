////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  XIP (execute in place) engine                                             //
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

module sockit_spi_xip #(
  parameter XAW = 24,             // bus address width
  parameter NOP = 32'h00000000    // no operation instruction (returned on error)
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // input bus (XIP requests)
  input  wire           xip_ren,  // read enable
  input  wire [XAW-1:0] xip_adr,  // address
  output wire    [31:0] xip_rdt,  // read data
  output wire           xip_wrq,  // wait request
  output wire           xip_err,  // error interrupt
  // output bus (interface to SPI master registers)
  output wire           fsm_wen,  // write enable
  output wire           fsm_ren,  // read  enable
  output reg            fsm_adr,  // address
  output reg     [31:0] fsm_wdt,  // write data
  input  wire    [31:0] fsm_rdt,  // read data
  input  wire           fsm_wrq,  // wait request
  // SPI master status
  input  wire           sts_cyc,  // read control/status
  // configuration
  input  wire [XAW-1:8] adr_off   // address offset
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

//                       x x f
//                       i i s
//                       p p m
//                       | | |
//                       e w w
//                       r r e
//                       r q n
// state names
localparam IDL_RST = 6'b 0_1_0_000;  // idle, reset
localparam CMD_WDT = 6'b 0_1_1_000;  // command write (load buffer)
localparam CMD_CTL = 6'b 0_1_1_001;  // command control (start cycle)
localparam CMD_STS = 6'b 0_1_0_01?;  // command status (wait for cycle end)
localparam DAT_CTL = 6'b 0_1_1_100;  // data control (start cycle)
localparam DAT_STS = 6'b 0_1_1_101;  // data read (read buffer)
localparam DAT_RDT = 6'b 0_0_0_11?;  // data read (read buffer)

// XIP state machine status
reg      [5:0] fsm_sts;  // current state
reg      [5:0] fsm_nxt;  // next state

// address adder
// reg  [XAW-1:0] adr_reg;  // input address register
// wire [XAW-1:0] adr_sum;  // input address + offset address

////////////////////////////////////////////////////////////////////////////////
// state machine                                                              //
////////////////////////////////////////////////////////////////////////////////

always @ (posedge clk, posedge rst)
if (rst) fsm_sts <= IDL_RST;
else     fsm_sts <= fsm_nxt;

always @ (*)
casez (fsm_sts)
  IDL_RST : begin
    fsm_adr = 1'bx;
    fsm_wdt = 32'hxxxx_xxxx;
    fsm_nxt =  xip_ren ? CMD_WDT : fsm_sts;
  end
  CMD_WDT : begin
    fsm_adr = 1'b0;
    fsm_wdt = {8'h0b, xip_adr + {adr_off, 8'h00}};
    fsm_nxt = ~fsm_wrq ? CMD_CTL : fsm_sts;
  end
  CMD_CTL : begin
    fsm_adr = 1'b1;
    fsm_wdt = 32'h001f_100a;
    fsm_nxt = ~fsm_wrq ? CMD_STS : fsm_sts;
  end
  CMD_STS : begin
    fsm_adr = 1'bx;
    fsm_wdt = 32'hxxxxxxxx;
    fsm_nxt = ~sts_cyc ? DAT_CTL : fsm_sts;
  end
  DAT_CTL : begin
    fsm_adr = 1'b1;
    fsm_wdt = 32'h0038_1008;
    fsm_nxt = ~fsm_wrq ? DAT_STS : fsm_sts;
  end
  DAT_STS : begin
    fsm_adr = 1'bx;
    fsm_wdt = 32'hxxxxxxxx;
    fsm_nxt = ~sts_cyc ? DAT_RDT : fsm_sts;
  end
  DAT_RDT : begin
    fsm_adr = 1'bx;
    fsm_wdt = 32'hxxxx_xxxx;
    fsm_nxt = IDL_RST;
  end
  default : begin
    fsm_adr = 1'bx;
    fsm_wdt = 32'hxxxx_xxxx;
    fsm_nxt = 6'b1_0_0_???;
  end
endcase

// XIP return signals
assign xip_rdt = fsm_rdt;
assign xip_wrq = fsm_sts[4];
assign xip_err = fsm_sts[5];

// register access signals
assign fsm_wen = fsm_sts[3];

endmodule
