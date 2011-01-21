module spi_slave_model #(
  parameter CPOL = 0,  // polarity
  parameter CPHA = 0,  // phase
  parameter MODE = 1   // mode (0-3wire, 1-SPI, 2-duo, 3-quad)
)(
  input wire ss_n,   //
  input wire sclk,   // serial clock
  inout wire mosi,   // master output slave input  / SIO[0]
  inout wire miso,   // maste input slave output   / SIO[1]
  inout wire wp_n,   // write protect (active low) / SIO[2]
  inout wire hold_n  // clock hold (active low)    / SIO[3]
);

reg       bit;
reg [7:0] byte;

always @ (posedge  sclk, posedge ss_n)
if (ss_n) bit  <= 1'bx;
else      bit  <= mosi;

always @ (posedge ~sclk, posedge ss_n)
if (ss_n) byte <= 7'hxx;
else      byte <= {byte[6:0], bit};

assign miso = byte[7];

endmodule
