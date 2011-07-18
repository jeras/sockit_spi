////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) testbench                                        //
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

`timescale 1us / 1ns

module spi_tb ();

////////////////////////////////////////////////////////////////////////////////
// local parameters and signals                                               //
////////////////////////////////////////////////////////////////////////////////

// register interface parameters
localparam AAW =  3;
localparam ADW = 32;
localparam ABW = ADW/8;

// XIP interface parameters
localparam XAW = 24;
localparam XDW = 32;
localparam XBW = XDW/8;

// DMA interface parameters
localparam DAW = 32;
localparam DDW = 32;
localparam DBW = XDW/8;

localparam DMA_SIZ = 1024;

// SPI parameters
localparam SSW = 8;

localparam CDC = 1'b1;

////////////////////////////////////////////////////////////////////////////////
// master instance signals                                                    //
////////////////////////////////////////////////////////////////////////////////

// system signals
reg clk_cpu, rst_cpu;
reg clk_spi, rst_spi;

// Avalon MM interface
reg            reg_wen;  // read enable
reg            reg_ren;  // read enable
reg  [AAW-1:0] reg_adr;  // address
reg  [ABW-1:0] reg_ben;  // byte enable
reg  [ADW-1:0] reg_wdt;  // write data
wire [ADW-1:0] reg_rdt;  // read data
wire           reg_wrq;  // wait request
wire           reg_err;  // error response
wire           reg_trn;  // transfer

// XIP bus
reg            xip_wen;  // read enable
reg            xip_ren;  // read enable
reg  [XAW-1:0] xip_adr;  // address
reg  [XBW-1:0] xip_ben;  // byte enable
reg  [XDW-1:0] xip_wdt;  // write data
wire [XDW-1:0] xip_rdt;  // read data
wire           xip_wrq;  // wait request
wire           xip_err;  // error response
wire           xip_trn;  // transfer
 
// DMA bus
wire           dma_wen;  // read enable
wire           dma_ren;  // read enable
wire [DAW-1:0] dma_adr;  // address
wire [DBW-1:0] dma_ben;  // byte enable
wire [DDW-1:0] dma_wdt;  // write data
wire [DDW-1:0] dma_rdt;  // read data
wire           dma_wrq;  // wait request
wire           dma_err;  // error response
wire           dma_trn;  // transfer

// DMA memory
reg  [DDW-1:0] dma_mem [0:DMA_SIZ-1];

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
// slave instance signals                                                     //
////////////////////////////////////////////////////////////////////////////////

// system signals
reg clk_slv, rst_slv;

// DMA bus (slave instance)
wire           slv_wen;  // read enable
wire           slv_ren;  // read enable
wire [DAW-1:0] slv_adr;  // address
wire [DBW-1:0] slv_ben;  // byte enable
wire [DDW-1:0] slv_wdt;  // write data
wire [DDW-1:0] slv_rdt;  // read data
wire           slv_wrq;  // wait request
wire           slv_err;  // error response
wire           slv_trn;  // transfer

// DMA memory (slave instance)
reg  [DDW-1:0] slv_mem [0:DMA_SIZ-1];

// IO buffer signals
wire           slv_ss_i,
               slv_ss_o,
               slv_ss_e;
wire           slv_sclk_i,
               slv_sclk_o,
               slv_sclk_e;
wire     [3:0] slv_sio_i,
               slv_sio_o,
               slv_sio_e;

////////////////////////////////////////////////////////////////////////////////
// SPI related signals                                                        //
////////////////////////////////////////////////////////////////////////////////

// SPI signals
wire [SSW-1:0] spi_ss_n;
wire           spi_sclk;
wire           spi_mosi;
wire           spi_miso;
wire           spi_wp_n;
wire           spi_hold_n;

////////////////////////////////////////////////////////////////////////////////
// testbench specific signals                                                 //
////////////////////////////////////////////////////////////////////////////////

// transfer data
reg  [ADW-1:0] data;

// testbench status descriptor
reg [64*8-1:0] test_name;

integer i;

// request for a dump file
initial begin
  $dumpfile("spi.fst");
  $dumpvars(0, spi_tb);
end

////////////////////////////////////////////////////////////////////////////////
// clock sources                                                              //
////////////////////////////////////////////////////////////////////////////////

// TODO enable asynchronous clocking

// CPU clock generation
initial    clk_cpu <= 1'b1;
always  #5 clk_cpu <= ~clk_cpu;

// SPI master clock generation
initial    clk_spi <= 1'b1;
always  #5 clk_spi <= ~clk_spi;

// slave clock generation
initial    clk_slv <= 1'b1;
always  #5 clk_slv <= ~clk_slv;

////////////////////////////////////////////////////////////////////////////////
// testbench                                                                  //
////////////////////////////////////////////////////////////////////////////////

// test sequence
initial begin
  // put register interface into idle
  reg_wen <= 1'b0;
  reg_ren <= 1'b0;
  // put XIP interface into idle
  xip_ren <= 1'b0;
  // reset generation
  rst_cpu  = 1'b1;
  rst_spi  = 1'b1;
  rst_slv  = 1'b1;
  repeat (2) @ (posedge clk_cpu); #1;
  rst_cpu  = 1'b0;
  rst_spi  = 1'b0;
  rst_slv  = 1'b0;

  IDLE (4);                // few clock periods

  IOWR (0, 32'h010100cc);  // write configuration

  IDLE (16);               // few clock periods
  test_name = "write 12B";

  // write data
  IOWR (3, 32'h02000000);  // write data    register
  IOWR (2, 32'h00001f17);  // write control register (32bit write)
  IOWR (3, "HELL");        // write flash data
  IOWR (2, 32'h00001f17);  // write control register (32bit write)
  IOWR (3, "O WO");        // write flash data
  IOWR (2, 32'h00001f17);  // write control register (32bit write)
  IOWR (3, "RLD!");        // write flash data
  IOWR (2, 32'h00001f17);  // write control register (32bit write)
  IOWR (2, 32'h00000010);  // write control register (cycle end)

  IDLE (16);               // few clock periods
  test_name = "read 12B";

  // read data
  IOWR (3, 32'h0b5a0000);  // write data    register
  IOWR (2, 32'h00001f17);  // write control register (32bit write)
  IOWR (2, 32'h00000713);  // write control register ( 8bit idle)
  IOWR (2, 32'h00001f1b);  // write control register (32bit read)
  IORD (3, data);          // read flash data
  IOWR (2, 32'h00001f1b);  // write control register (32bit read)
  IORD (3, data);          // read flash data
  IOWR (2, 32'h00001f1b);  // write control register (32bit read)
  IORD (3, data);          // read flash data
  IOWR (2, 32'h00000010);  // write control register (cycle end)

  IDLE (200);              // few clock periods

  IDLE (16);               // few clock periods
  test_name = "DMA -> SPI";

  IOWR (3, 32'h02000000);  // write data    register
  IOWR (2, 32'h00001f17);  // write control register (32bit write)
  IOWR (5, 32'h80000003);  // request a DMA read, SPI write transfer
  POLL (5, 32'h80000000);  // wait for DMA to finish
  IOWR (2, 32'h00000010);  // write control register (cycle end)

  IDLE (16);               // few clock periods
  test_name = "SPI -> DMA";

  IOWR (3, 32'h0b5a0000);  // write data    register
  IOWR (2, 32'h00001f17);  // write control register (32bit write)
  IOWR (2, 32'h00000713);  // write control register ( 8bit idle)
  IOWR (5, 32'h00000003);  // request a SPI read, DMA write transfer
  POLL (5, 32'h80000000);  // wait for DMA to finish
  IOWR (2, 32'h00000010);  // write control register (cycle end)

  IDLE (200);              // few clock periods

//  IOWR (3, 32'h3b5a0000);  // write data    register (command fast read dual output)
//  IOWR (2, 32'h00174007);  // write control register (enable a chip and start a 4 byte write)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h00104001);  // write control register (enable a chip and start a 1 byte dummy)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h00388007);  // write control register (enable a chip and start a 4 byte read)
//  POLL (2, 32'h0000000f);
//  IORD (3, data);          // read flash data
//
//  IDLE (16);               // few clock periods
//
//  IOWR (3, 32'h6b5a0000);  // write data    register (command fast read quad output)
//  IOWR (2, 32'h00174007);  // write control register (enable a chip and start a 4 byte write)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h00104001);  // write control register (enable a chip and start a 1 byte dummy)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h0038c007);  // write control register (enable a chip and start a 4 byte read)
//  POLL (2, 32'h0000000f);
//  IORD (3, data);          // read flash data
//
//  IDLE (16);               // few clock periods
//
//  IOWR (3, 32'hbb000000);  // write data    register (command fast read dual IO)
//  IOWR (2, 32'h00174001);  // write control register (send command)
//  POLL (2, 32'h0000000f);
//  IOWR (3, 32'h5a000000);  // write data    register (address and dummy)
//  IOWR (2, 32'h00138007);  // write control register (send address and dummy)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h00388007);  // write control register (4 byte read)
//  POLL (2, 32'h0000000f);
//  IORD (3, data);          // read flash data
//
//  IDLE (16);               // few clock periods
//
//  IOWR (3, 32'heb000000);  // write data    register (command fast read quad IO)
//  IOWR (2, 32'h00174001);  // write control register (send command)
//  POLL (2, 32'h0000000f);
//  IOWR (3, 32'h5a000000);  // write data    register (address and dummy)
//  IOWR (2, 32'h0017c007);  // write control register (send address and dummy)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h0038c007);  // write control register (4 byte read)
//  POLL (2, 32'h0000000f);
//  IORD (3, data);          // read flash data
//
//  IDLE (16);               // few clock periods
//
//  IOWR (1, 32'h00000001);  // enable XIP
//
//  xip_cyc (0, 24'h000000, 4'hf, 32'hxxxxxxxx, data);  // read data from XIP port

  test_name = "END";
  IDLE (16);               // few clock periods

  $finish;  // end simulation
end

// end test on timeout
initial begin
  repeat (5000) @ (posedge clk_cpu);
  $finish;  // end simulation
end

////////////////////////////////////////////////////////////////////////////////
// register bus tasks                                                         //
////////////////////////////////////////////////////////////////////////////////

// Avalon MM cycle transfer cycle end status
assign reg_trn = (reg_ren | reg_wen) & ~reg_wrq;

task reg_cyc;
  input            r_w;  // 0-read or 1-write cycle
  input  [AAW-1:0] adr;
  input  [ABW-1:0] ben;
  input  [ADW-1:0] wdt;
  output [ADW-1:0] rdt;
// task reg_cyc (
//   input            r_w,  // 0-read or 1-write cycle
//   input  [AAW-1:0] adr,
//   input  [ABW-1:0] ben,
//   input  [ADW-1:0] wdt,
//   output [ADW-1:0] rdt
// );
begin
//  $display ("REG cycle start: T=%10tns, %s adr=%08x ben=%04b wdt=%08x", $time/1000.0, r_w?"write":"read ", adr, ben, wdt);
  // start an Avalon cycle
  reg_ren <= ~r_w;
  reg_wen <=  r_w;
  reg_adr <=  adr;
  reg_ben <=  ben;
  reg_wdt <=  wdt;
  // wait for waitrequest to be retracted
  @ (posedge clk_cpu); while (~reg_trn) @ (posedge clk_cpu);
  // end Avalon cycle
  reg_ren <=      1'b0  ;
  reg_wen <=      1'b0  ;
  reg_adr <= {AAW{1'bx}};
  reg_ben <= {ABW{1'bx}};
  reg_wdt <= {ADW{1'bx}};
  // read data
  rdt = reg_rdt;
//  $display ("REG cycle end  : T=%10tns, rdt=%08x", $time/1000.0, rdt);
end
endtask

// IO register write
task IOWR (input [AAW-1:0] adr,  input [ADW-1:0] wdt);
  reg [ADW-1:0] rdt;
begin
  reg_cyc (1'b1, adr, 4'hf, wdt, rdt);
end
endtask

// IO register read
task IORD (input [AAW-1:0] adr, output [ADW-1:0] rdt);
begin
  reg_cyc (1'b0, adr, 4'hf, {ADW{1'bx}}, rdt);
end
endtask

// polling for end of cycle
task POLL (input [AAW-1:0] adr,  input [ADW-1:0] msk);
  reg [ADW-1:0] rdt;
begin
  rdt = msk;
  while (rdt & msk)
  IORD (adr, rdt);
end
endtask

// idle for a specified number of clock periods
task IDLE (input integer num);
begin
  repeat (num) @ (posedge clk_cpu);
end
endtask

////////////////////////////////////////////////////////////////////////////////
// XIP bus tasks                                                              //
////////////////////////////////////////////////////////////////////////////////

// transfer cycle end status
assign xip_trn = (xip_ren | xip_wen) & ~xip_wrq;

task xip_cyc;
  input            r_w;  // 0-read or 1-write cycle
  input  [XAW-1:0] adr;
  input  [XBW-1:0] ben;
  input  [XDW-1:0] wdt;
  output [XDW-1:0] rdt;
// task reg_cyc (
//   input            r_w,  // 0-read or 1-write cycle
//   input  [XAW-1:0] adr,
//   input  [XBW-1:0] ben,
//   input  [XDW-1:0] wdt,
//   output [XDW-1:0] rdt
// );
begin
//  $display ("XIP cycle start: T=%10tns, %s adr=%08x ben=%04b wdt=%08x", $time/1000.0, r_w?"write":"read ", adr, ben, wdt);
  // begin cycle
  xip_ren <= ~r_w;
  xip_wen <=  r_w;
  xip_adr <=  adr;
  xip_ben <=  ben;
  xip_wdt <=  wdt;
  // wait for waitrequest to be retracted
  @ (posedge clk_cpu); while (~xip_trn) @ (posedge clk_cpu);
  // end cycle
  xip_ren <=      1'b0  ;
  xip_wen <=      1'b0  ;
  xip_adr <= {XAW{1'bx}};
  xip_ben <= {XBW{1'bx}};
  xip_wdt <= {XDW{1'bx}};
  // read data
  rdt = xip_rdt;
//  $display ("XIP cycle end  : T=%10tns, rdt=%08x", $time/1000.0, rdt);
end
endtask

////////////////////////////////////////////////////////////////////////////////
// DMA memory model                                                           //
////////////////////////////////////////////////////////////////////////////////

// write access
always @ (posedge clk_cpu)
if (dma_wen & ~dma_wrq) begin
  if (dma_ben[3])  dma_mem[dma_adr[DAW-1:2]][8*3+:8] = dma_wdt[8*3+:8];
  if (dma_ben[2])  dma_mem[dma_adr[DAW-1:2]][8*2+:8] = dma_wdt[8*2+:8];
  if (dma_ben[1])  dma_mem[dma_adr[DAW-1:2]][8*1+:8] = dma_wdt[8*1+:8];
  if (dma_ben[0])  dma_mem[dma_adr[DAW-1:2]][8*0+:8] = dma_wdt[8*0+:8];
end

// read access
assign dma_rdt = (dma_ren & ~dma_wrq) ? dma_mem[dma_adr[DAW-1:2]] : 32'hxxxxxxxx;

// timing TODO randomization
assign dma_wrq = 1'b0;

// error response
assign dma_err = 1'b0;

// initializing memory contents
initial  $readmemh("dma_mem.hex", dma_mem);

////////////////////////////////////////////////////////////////////////////////
// SPI controller master instance                                             //
////////////////////////////////////////////////////////////////////////////////

sockit_spi #(
  .XAW         (XAW),
  .SSW         (SSW),
  .CDC         (CDC)
) sockit_spi (
  // system signals (used by the CPU bus interface)
  .clk_cpu     (clk_cpu),
  .rst_cpu     (rst_cpu),
  .clk_spi     (clk_spi),
  .rst_spi     (rst_spi),
  // register interface
  .reg_wen     (reg_wen),
  .reg_ren     (reg_ren),
  .reg_adr     (reg_adr),
  .reg_wdt     (reg_wdt),
  .reg_rdt     (reg_rdt),
  .reg_wrq     (reg_wrq),
  .reg_err     (reg_err),
  .reg_irq     (reg_irq),
  // XIP interface
  .xip_ren     (xip_ren),
  .xip_adr     (xip_adr),
  .xip_ben     (xip_ben),
  .xip_wdt     (xip_wdt),
  .xip_rdt     (xip_rdt),
  .xip_wrq     (xip_wrq),
  .xip_err     (xip_err),
  // DMA interface
  .dma_ren     (dma_ren),
  .dma_adr     (dma_adr),
  .dma_ben     (dma_ben),
  .dma_wdt     (dma_wdt),
  .dma_rdt     (dma_rdt),
  .dma_wrq     (dma_wrq),
  .dma_err     (dma_err),
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
// SPI master tristate buffers                                                //
////////////////////////////////////////////////////////////////////////////////

// clock
bufif1 spi_sclk_b  (spi_sclk, spi_sclk_o, spi_sclk_e);
assign spi_sclk_i = spi_sclk;

// data
bufif1 spi_sio_b [3:0] ({spi_hold_n, spi_wp_n, spi_miso, spi_mosi}, spi_sio_o, spi_sio_e);
assign spi_sio_i =      {spi_hold_n, spi_wp_n, spi_miso, spi_mosi};

// slave select (active low)
bufif1 spi_ss_b [SSW-1:0] (spi_ss_n, ~spi_ss_o, spi_ss_e);
assign spi_ss_i =          spi_ss_n;

////////////////////////////////////////////////////////////////////////////////
// SPI controller master instance                                             //
////////////////////////////////////////////////////////////////////////////////

sockit_spi #(
  .XAW         (XAW),
  .SSW         (1),
  .CDC         (CDC)
) sockit_spi_slv (
  // system signals (used by the CPU bus interface)
  .clk_cpu     (clk_slv),
  .rst_cpu     (rst_slv),
  .clk_spi     (clk_slv),
  .rst_spi     (rst_slv),
  // register interface
  .reg_wen     ( 1'b0),
  .reg_ren     ( 1'b0),
  .reg_adr     ( 3'd0),
  .reg_wdt     (32'd0),
  .reg_rdt     (     ),
  .reg_wrq     (     ),
  .reg_err     (     ),
  .reg_irq     (     ),
  // XIP interface
  .xip_ren     ( 1'b0),
  .xip_adr     ( 1'b0),
  .xip_ben     ( 3'd0),
  .xip_wdt     (32'd0),
  .xip_rdt     (     ),
  .xip_wrq     (     ),
  .xip_err     (     ),
  // DMA interface
  .dma_ren     (slv_ren),
  .dma_adr     (slv_adr),
  .dma_ben     (slv_ben),
  .dma_wdt     (slv_wdt),
  .dma_rdt     (slv_rdt),
  .dma_wrq     (slv_wrq),
  .dma_err     (slv_err),
  // SPI signals (should be connected to tristate IO pads)
  // serial clock
  .spi_sclk_i  (slv_sclk_i),
  .spi_sclk_o  (slv_sclk_o),
  .spi_sclk_e  (slv_sclk_e),
  // serial input output SIO[3:0] or {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  .spi_sio_i   (slv_sio_i),
  .spi_sio_o   (slv_sio_o),
  .spi_sio_e   (slv_sio_e),
  // active low slave select signal
  .spi_ss_i    (slv_ss_i),
  .spi_ss_o    (slv_ss_o),
  .spi_ss_e    (slv_ss_e)
);

////////////////////////////////////////////////////////////////////////////////
// SPI slave tristate buffers                                                //
////////////////////////////////////////////////////////////////////////////////

// clock
bufif1 slv_sclk_b  (spi_sclk, slv_sclk_o, slv_sclk_e);
assign slv_sclk_i = spi_sclk;

// data
bufif1 slv_sio [3:0] ({spi_hold_n, spi_wp_n, spi_miso, spi_mosi}, slv_sio_o, slv_sio_e);
assign slv_sio_i =    {spi_hold_n, spi_wp_n, spi_miso, spi_mosi};

// slave select (active low)
bufif1 slv_ss_b  (spi_ss_n[0], ~slv_ss_o, slv_ss_e);
assign slv_ss_i = spi_ss_n[0];

////////////////////////////////////////////////////////////////////////////////
// DMA memory model                                                           //
////////////////////////////////////////////////////////////////////////////////

// write access
always @ (posedge clk_slv)
if (slv_wen & ~slv_wrq) begin
  if (slv_ben[3])  slv_mem[slv_adr[DAW-1:2]][8*3+:8] = slv_wdt[8*3+:8];
  if (slv_ben[2])  slv_mem[slv_adr[DAW-1:2]][8*2+:8] = slv_wdt[8*2+:8];
  if (slv_ben[1])  slv_mem[slv_adr[DAW-1:2]][8*1+:8] = slv_wdt[8*1+:8];
  if (slv_ben[0])  slv_mem[slv_adr[DAW-1:2]][8*0+:8] = slv_wdt[8*0+:8];
end

// read access
assign slv_rdt = (slv_ren & ~slv_wrq) ? slv_mem[slv_adr[DAW-1:2]] : 32'hxxxxxxxx;

// timing TODO randomization
assign slv_wrq = 1'b0;

// error response
assign slv_err = 1'b0;

// initializing memory contents
initial  $readmemh("slv_mem.hex", slv_mem);

////////////////////////////////////////////////////////////////////////////////
// SPI slave (serial Flash)                                                   //
////////////////////////////////////////////////////////////////////////////////

// loopback for debug purposes
//assign spi_miso = ~spi_ss_n[0] ? spi_mosi : 1'bz;

// SPI slave model
spi_flash_model #(
  .DIOM      (2'd1),
  .MODE      (2'd0)
) slave_spi (
  .ss_n      (spi_ss_n[0]),
  .sclk      (spi_sclk),
  .mosi      (spi_mosi),
  .miso      (spi_miso),
  .wp_n      (spi_wp_n),
  .hold_n    (spi_hold_n)
);

// SPI slave model
spi_slave_model #(
  .MODE_DAT  (2'd0),
  .MODE_CLK  (2'd0),
  .DLY       (32)
) slave_3wire (
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
