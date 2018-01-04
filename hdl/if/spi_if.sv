interface spi_if #(
  int unsigned DW = 4,  // data width
  int unsigned SN = 8   // select width
);

// serial clock
logic          clk_i;
logic          clk_o;
logic          clk_e;
// quad IO [HOLD#, WP#, MISO, MOSI]
logic [DW-1:0] sio_i;
logic [DW-1:0] sio_o;
logic [DW-1:0] sio_e;
// primary slave select
logic [SN-1:0] ssn_i;
logic [SN-1:0] ssn_o;
logic [SN-1:0] ssn_e;

// master
modport m (
  input  clk_i,
  output clk_o,
  output clk_e,
  input  sio_i,
  output sio_o,
  output sio_e,
  input  ssn_i,
  output ssn_o,
  output ssn_e
);

// slave
modport s (
  output clk_i,
  input  clk_o,
  input  clk_e,
  output sio_i,
  input  sio_o,
  input  sio_e,
  output ssn_i,
  input  ssn_o,
  input  ssn_e
);

endinterface: spi_if
