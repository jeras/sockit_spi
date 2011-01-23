module spi_slave_model #(
  parameter DLY  = 8,     // data delay
  parameter CPOL = 1'b0,  // polarity
  parameter CPHA = 1'b0,  // phase
  parameter MODE = 2'b01  // mode (0-3wire, 1-SPI, 2-duo, 3-quad)
)(
  input wire ss_n,   //
  input wire sclk,   // serial clock
  inout wire mosi,   // master output slave input  / SIO[0]
  inout wire miso,   // maste input slave output   / SIO[1]
  inout wire wp_n,   // write protect (active low) / SIO[2]
  inout wire hold_n  // clock hold (active low)    / SIO[3]
);

localparam IOW = MODE[1] ? (MODE[0] ? 4 : 2) : 1;

reg     [IOW-1:0] reg_iow;
reg [DLY*IOW-1:0] reg_dat;

always @ (posedge  sclk, posedge ss_n)
if (ss_n) reg_iow  <= {IOW{1'bx}};
else      reg_iow  <= mosi;

always @ (posedge ~sclk, posedge ss_n)
if (ss_n) reg_dat <= {DLY{1'bx}};
else      reg_dat <= {reg_dat[DLY-2:0], reg_iow};

assign miso = reg_dat[DLY-1];

endmodule
