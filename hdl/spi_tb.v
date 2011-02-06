////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) testbench                                        //
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

`timescale 1us / 1ns

module spi_tb ();

////////////////////////////////////////////////////////////////////////////////
// local parameters and signals                                               //
////////////////////////////////////////////////////////////////////////////////

localparam ADW = 32;
localparam AAW = 32;
localparam ABW = ADW/8;
localparam SSW = 8;

// system signals
reg clk, rst;

// Avalon MM interfacie
reg            avalon_write;
reg            avalon_read;
reg  [AAW-1:0] avalon_address;
reg  [ABW-1:0] avalon_byteenable;
reg  [ADW-1:0] avalon_writedata;
wire [ADW-1:0] avalon_readdata;
wire           avalon_waitrequest;

wire           avalon_transfer;

reg  [ADW-1:0] data;

// SPI signals
wire [SSW-1:0] spi_ss_n;
wire           spi_sclk;
wire           spi_mosi;
wire           spi_miso;
wire           spi_wp_n;
wire           spi_hold_n;

// IO buffer signals
wire [SSW-1:0] spi_ss_i,
               spi_ss_o,
               spi_ss_e;
wire           spi_sclk_i,
               spi_sclk_o,
               spi_sclk_e;
wire     [3:0] spi_sio_i,
               spi_sio_o,
               spi_sio_e;

////////////////////////////////////////////////////////////////////////////////
// testbench                                                                  //
////////////////////////////////////////////////////////////////////////////////

// request for a dumpfile
initial begin
  $dumpfile("spi.vcd");
  $dumpvars(0, spi_tb);
end

// clock generation
initial    clk <= 1'b1;
always  #5 clk <= ~clk;

// test sequence
initial begin
  avalon_write <= 1'b0;
  avalon_read  <= 1'b0;
  // reset generation
  rst = 1'b1;
  repeat (2) @ (posedge clk); #1;
  rst = 1'b0;
  repeat (4) @ (posedge clk);

  // write slave select and clock divider
  avalon_cycle (1, 4'h2, 4'hf, 32'h0200_0fc4, data);
  // write data register
  avalon_cycle (1, 4'h0, 4'hf, 32'h0123_4567, data);
  // write control register (enable a chip and start a 4 byte cycle)
  avalon_cycle (1, 4'h1, 4'hf, 32'h8000_0708, data);
  repeat (500) @ (posedge clk);
  $finish();
end

////////////////////////////////////////////////////////////////////////////////
// avalon tasks                                                               //
////////////////////////////////////////////////////////////////////////////////

// avalon cycle transfer cycle end status
assign avalon_transfer = (avalon_read | avalon_write) & ~avalon_waitrequest;

task avalon_cycle (
  input            r_w,  // 0-read or 1-write cycle
  input  [AAW-1:0] adr,
  input  [ABW-1:0] ben,
  input  [ADW-1:0] wdt,
  output [ADW-1:0] rdt
);
begin
  $display ("Avalon MM cycle start: T=%10tns, %s address=%08x byteenable=%04b writedata=%08x", $time/1000.0, r_w?"write":"read ", adr, ben, wdt);
  // start an Avalon cycle
  avalon_read       <= ~r_w;
  avalon_write      <=  r_w;
  avalon_address    <=  adr;
  avalon_byteenable <=  ben;
  avalon_writedata  <=  wdt;
  // wait for waitrequest to be retracted
  @ (posedge clk); while (~avalon_transfer) @ (posedge clk);
  // end Avalon cycle
  avalon_read       <= 1'b0;
  avalon_write      <= 1'b0;
  // read data
  rdt = avalon_readdata;
  $display ("Avalon MM cycle end  : T=%10tns, readdata=%08x", $time/1000.0, rdt);
end
endtask

////////////////////////////////////////////////////////////////////////////////
// spi controller instance                                                    //
////////////////////////////////////////////////////////////////////////////////

spi #(
  .SSW         (SSW)
) spi (
  // system signals (used by the CPU bus interface)
  .clk         (clk),
  .rst         (rst),
  // avalon interface
  .bus_wen     (avalon_write      ),
  .bus_ren     (avalon_read       ),
  .bus_adr     (avalon_address    ),
  .bus_wdt     (avalon_writedata  ),
  .bus_rdt     (avalon_readdata   ),
  .bus_wrq     (avalon_waitrequest),
  .bus_irq     (avalon_interrupt  ),
  // SPI signals (should be connected to tristate IO pads)
  // serial clock
  .spi_sclk_i  (spi_sclk_i),
  .spi_sclk_o  (spi_sclk_o),
  .spi_sclk_e  (spi_sclk_e),
  // serial input output SIO[3:0] or {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  .spi_sio_i   (spi_sio_i),
  .spi_sio_o   (spi_sio_o),
  .spi_sio_e   (spi_sio_e),
  // active low slave select signal
  .spi_ss_i    (spi_ss_i),
  .spi_ss_o    (spi_ss_o),
  .spi_ss_e    (spi_ss_e)
);

////////////////////////////////////////////////////////////////////////////////
// SPI tristate buffers                                                       //
////////////////////////////////////////////////////////////////////////////////

// clock
bufif1 buffer_sclk (spi_sclk, spi_sclk_o, spi_sclk_e);
assign spi_sclk_i = spi_sclk;

// data
bufif1 buffer_sio [3:0] ({spi_hold_n, spi_wp_n, spi_miso, spi_mosi}, spi_sio_o, spi_sio_e);
assign spi_sio_i =       {spi_hold_n, spi_wp_n, spi_miso, spi_mosi};

// slave select (active low)
bufif1 buffer_ss_n [SSW-1:0] (spi_ss_n, ~spi_ss_o, spi_ss_e);
assign spi_ss_i =             spi_ss_n;

////////////////////////////////////////////////////////////////////////////////
// SPI slave (serial Flash)                                                   //
////////////////////////////////////////////////////////////////////////////////

// loopback for debug purposes
//assign spi_miso = ~spi_ss_n[0] ? spi_mosi : 1'bz;

// SPI slave model
spi_slave_model #(
  .MODE_DAT  (2'd0),
  .MODE_CLK  (2'd0),
  .DLY       (32)
) slave_3wire (
  .ss_n      (spi_ss_n[0]),
  .sclk      (spi_sclk),
  .mosi      (spi_mosi),
  .miso      (spi_miso),
  .wp_n      (spi_wp_n),
  .hold_n    (spi_hold_n)
);

// SPI slave model
spi_slave_model #(
  .MODE_DAT  (2'd1),
  .MODE_CLK  (2'd0),
  .DLY       (32)
) slave_spi (
  .ss_n      (spi_ss_n[1]),
  .sclk      (spi_sclk),
  .mosi      (spi_mosi),
  .miso      (spi_miso),
  .wp_n      (spi_wp_n),
  .hold_n    (spi_hold_n)
);

//// Spansion serial Flash
//s25fl129p00 #(
//  .mem_file_name ("none")
//) Flash_1 (
//  .SCK     (spi_sclk),
//  .SI      (spi_mosi),
//  .CSNeg   (spi_ss_n[1]),
//  .HOLDNeg (spi_hold_n),
//  .WPNeg   (spi_wp_n),
//  .SO      (spi_miso)
//);
//
//// Spansion serial Flash
//s25fl032a #(
//  .mem_file_name ("none")
//) Flash_2 (
//  .SCK     (spi_sclk),
//  .SI      (spi_mosi),
//  .CSNeg   (spi_ss_n[2]),
//  .HOLDNeg (1'b1),
//  .WNeg    (1'b1),
//  .SO      (spi_miso)
//);
//
//// Numonyx serial Flash
//m25p80 
//Flash_3 (
//  .c         (spi_sclk),
//  .data_in   (spi_mosi),
//  .s         (spi_ss_n[3]),
//  .w         (1'b1),
//  .hold      (1'b1),
//  .data_out  (spi_miso)
//);
//defparam Flash.mem_access.initfile = "hdl/bench/numonyx/initM25P80.txt";

endmodule
