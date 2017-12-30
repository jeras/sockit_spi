////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  memory mapped configuration, control and status registers                 //
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
//  Address space                                                             //
//                                                                            //
//  adr | reg name, short description                                         //
// -----+-------------------------------------------------------------------- //
//  0x0 | spi_cfg - SPI configuration                                         //
//  0x1 | spi_ctl - SPI control/status                                        //
//  0x2 | spi_irq - SPI interrupts                                            //
//  0x3 | adr_off - AXI address offset                                        //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Configuration register                                                     //
//                                                                            //
// Reset values of each bit in the configuration register are defined by the  //
// CFG_RST[31:0] parameter, another parameter CFG_MSK[31:0] defines which     //
// configuration field is read/ write (mask=0) and which are read only, fixed //
// at the reset value (mask=0).                                               //
//                                                                            //
// Configuration register fields:                                             //
// [31:24] - sss - slave select selector                                      //
// [23:17] - sss - reserved (for configuring XIP for specific SPI devices)    //
// [   16] - end - bus endianness (0 - little, 1 - big) for XIP, DMA          //
// [15:11] - dly - SPI IO output to input switch delay (1 to 32 clk periods)  //
// [   10] - prf - read prefetch (0 - single, 1 - double) for DMA slave mode  //
// [ 9: 8] - bts - bus transfer size (0 - 1 byte  ) for DMA slave mode        //
//               -                   (1 - 2 bytes )                           //
//               -                   (2 - reserved)                           //
//               -                   (3 - 4 bytes )                           //
// [    6] - dir - shift direction (0 - LSB first, 1 - MSB first)             //
// [ 5: 4] - iom - SPI data IO mode (0 - 3-wire) for XIP, slave mode          //
//               -                  (1 - SPI   )                              //
//               -                  (2 - dual  )                              //
//               -                  (3 - quad  )                              //
// [    3] - soe - slave select output enable                                 //
// [    2] - coe - clock output enable                                        //
// [    1] - pol - clock polarity                                             //
// [    0] - pha - clock phase                                                //
//                                                                            //
// Slave select selector fields enable the use of each of up to 8 slave       //
// select signals, so that it is possible to enable more than one lave at the //
// same time (broadcast mode).                                                //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Parameterization register:                                                 //
//                                                                            //
// The parameterization register holds parameters, which specify what         //
// functionality is enabled in the module at compile time.                    //
//                                                                            //
// Parameterization register fields:                                          //
// [ 7: 6] - ffo - clock domain crossing FIFO input  size                     //
// [ 5: 4] - ffo - clock domain crossing FIFO output size                     //
// [    3] - ??? - TODO                                                       //
// [ 2: 0] - ssn - number of slave select ports (from 1 to 8 signals)         //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi_reg #(
  // configuration (register reset values and masks)
  parameter CFG_RST = 32'h00000000,  // configuration register reset value
  parameter CFG_MSK = 32'hffffffff,  // configuration register implementation mask
  parameter ADR_ROF = 32'h00000000,  // address write offset
  parameter ADR_WOF = 32'h00000000,  // address read  offset
  // port widths
  parameter XAW     =           24   // XIP address width
)(
  // AMBA AXI4-Lite
  axi4_lite_if.s         axi,
  // SPI/XIP/DMA configuration
  output sockit_spi_pkg::cfg_t  spi_cfg,  // configuration register
  // address offsets
  output logic    [31:0] adr_rof,  // address read  offset
  output logic    [31:0] adr_wof,  // address write offset
  // streams
  sockit_spi_if.s        cmc  // command
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// decoded register access signals
logic  wen_spi, ren_spi;  // SPI control/status
logic  wen_dat, ren_dat;  // SPI data
logic  wen_dma, ren_dma;  // DMA control/status

//
logic    [31:0] spi_par;  // SPI parameterization
logic    [31:0] spi_sts;  // SPI status

////////////////////////////////////////////////////////////////////////////////
// read access                                                                //
////////////////////////////////////////////////////////////////////////////////

// read address
always_ff @(posedge axi.ACLK)
if (axi.ARVALID & axi.ARREADY)
  raddr <= axi.ARADDR;
end

// read address channel is never delayed
always_ff @(posedge axi.ACLK, negedge axi.ARESETn)
if (~axi.ARESETn) begin
  axi.ARREADY = 1'b0;
end else begin
  axi.ARREADY = 1'b1;
end

// read data
always_ff @(posedge axi.ACLK)
case (raddr)
  3'd0 : axi.RDATA <=      spi_cfg;  // SPI configuration
  3'd1 : axi.RDATA <=      spi_par;  // SPI parameterization
  3'd2 : axi.RDATA <=      spi_sts;  // SPI status
  3'd4 : axi.RDATA <= 32'hxxxxxxxx;  // SPI interrupts
  3'd6 : axi.RDATA <=      adr_rof;  // address read  offset
  3'd7 : axi.RDATA <=      adr_wof;  // address write offset
endcase

// read data channel is never delayed
always_ff @(posedge axi.ACLK, negedge axi.ARESETn)
if (~axi.ARESETn) begin
  axi.RREADY = 1'b0;
end else begin // TODO condition
  axi.RREADY = 1'b1;
end

////////////////////////////////////////////////////////////////////////////////
// interrupts                                                                 //
////////////////////////////////////////////////////////////////////////////////

// interrupt
assign reg_irq = 1'b0; // TODO

////////////////////////////////////////////////////////////////////////////////
// configuration registers                                                    //
////////////////////////////////////////////////////////////////////////////////

// SPI configuration (write access)
always_ff @(posedge clk, posedge rst)
if (rst) begin
  spi_cfg <= CFG_RST;
end else if (reg_wen & (reg_adr == 3'd0)) begin
  spi_cfg <= CFG_RST & ~CFG_MSK | reg_wdt & CFG_MSK;
end

// SPI parameterization (read access)
assign spi_par =  32'h0;

// SPI status
assign spi_sts =  32'h0; // TODO

// XIP/DMA address offsets
always_ff @(posedge clk, posedge rst)
if (rst) begin
                        adr_rof <= ADR_ROF [31:0];
                        adr_wof <= ADR_WOF [31:0];
end else if (reg_wen) begin
  if (reg_adr == 3'd6)  adr_rof <= reg_wdt [31:0];
  if (reg_adr == 3'd7)  adr_wof <= reg_wdt [31:0];
end

////////////////////////////////////////////////////////////////////////////////
// command output                                                             //
////////////////////////////////////////////////////////////////////////////////

// data output
always_ff @(posedge clk)
if (wen_dat)  cmo_dat <= reg_wdt;

// command output
assign cmo_vld = wen_spi;
assign cmo_ctl = {reg_wdt[12:8], reg_wdt[6:0]};

////////////////////////////////////////////////////////////////////////////////
// command input register                                                     //
////////////////////////////////////////////////////////////////////////////////

endmodule: sockit_spi_reg
