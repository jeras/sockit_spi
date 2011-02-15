////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  XIP (execute in place) engine                                             //
//                                                                            //
//  Copyright (C) 2008  Iztok Jeras                                           //
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
  parameter XAW = 24,                // bus address width
  parameter NOP = 32'h00000000       // no operation instruction (returned on error)
)(
  // system signals
  input  wire           clk,         // clock
  input  wire           rst,         // reset
  // input bus (XIP requests)
  input  wire           bsi_wen,     // write enable
  input  wire           bsi_ren,     // read enable
  input  wire [XAW-1:0] bsi_adr,     // address
  input  wire    [31:0] bsi_wdt,     // write data
  output wire    [31:0] bsi_rdt,     // read data
  output reg            bsi_wrq,     // wait request
  // output bus (interface to SPI master registers)
  output reg            bso_wen,     // write enable
  output reg            bso_ren,     // read enable
  output reg            bso_adr,     // address
  output reg     [31:0] bso_wdt,     // write data
  input  wire    [31:0] bso_rdt,     // read data
  input  wire           bso_wrq,     // wait request
  // configuration
  input  wire [XAW-1:8] xip_adr,     // address offset
  // status
  output wire [XAW-1:8] xip_err      // error interrupt
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// state names
localparam IDL_XXX = 4'h0;  // idle
localparam CMD_WDT = 4'h1;  // command write (load buffer)
localparam CMD_CTL = 4'h2;  // command control (start cycle)
localparam CMD_STS = 4'h3;  // command status (wait for cycle end)
localparam ADR_WDT = 4'h4;  // address write (load buffer)
localparam ADR_CTL = 4'h5;  // address control (start cycle)
localparam ADR_STS = 4'h6;  // address status (wait for cycle end)
localparam DAT_CTL = 4'h7;  // data control (start cycle)
localparam DAT_RDT = 4'h8;  // data read (read buffer)

// finite state machine
reg      [3:0] fsm_sts;  // current state

// address adder
reg  [XAW-1:0] adr_reg;  // input address register
wire [XAW-1:0] adr_sum;  // input address + offset address

////////////////////////////////////////////////////////////////////////////////
// state machine                                                              //
////////////////////////////////////////////////////////////////////////////////

always @ (posedge clk, posedge rst)
if (rst) begin
  fsm_sts <= IDL_XXX;
  bsi_wrq <= 1'b1;  // there is no data available
  bso_wen <= 1'b0;
  bso_ren <= 1'b0;
  bso_adr <= 1'h0;
  bso_wdt <= 32'h000000;
end else begin
  case (fsm_sts)
    IDL_XXX : begin
      if (bsi_ren) begin
      end
    end
    CMD_WDT : begin
    end
    CMD_CTL : begin
    end
    CMD_STS : begin
    end
    ADR_WDT : begin
    end
    ADR_CTL : begin
    end
    ADR_STS : begin
    end
    DAT_CTL : begin
    end
    DAT_RDT : begin
    end
  endcase
end


endmodule
