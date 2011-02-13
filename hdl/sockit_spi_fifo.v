module sockit_spi_fifo #(
  parameter FSZ = 1024  // FIFO deepth
)(
  // system signals
  input  wire           clk,         // clock
  input  wire           rst,         // reset
  // input bus
  input  wire           bsi_wen,     // write enable
  input  wire           bsi_ren,     // read enable
  input  wire [BAW-1:0] bsi_adr,     // address
  input  wire    [31:0] bsi_wdt,     // write data
  output wire    [31:0] bsi_rdt,     // read data
  output wire           bsi_wrq,     // wait request
  // output bus
  output wire           bso_wen,     // write enable
  output wire           bso_ren,     // read enable
  output wire [BAW-1:0] bso_adr,     // address
  output wire    [31:0] bso_wdt,     // write data
  input  wire    [31:0] bso_rdt,     // read data
  input  wire           bso_wrq,     // wait request
);

endmodule
