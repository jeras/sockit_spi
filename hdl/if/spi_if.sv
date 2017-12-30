interface spi_if #(
  int unsigned DW = 4,  // data width
  int unsigned SN = 8   // select width
);

// serial clock
logic          clk_i;
logic          clk_o;
logic          clk_t;
// quad IO [HOLD#, WP#, MISO, MOSI]
logic [DW-1:0] sio_i;
logic [DW-1:0] sio_o;
logic [DW-1:0] sio_t;
// primary slave select
logic [SN-1:0] ssn_i;
logic [SN-1:0] ssn_o;
logic [SN-1:0] ssn_t;

// master
modport m (
  input  clk_i,
  output clk_o,
  output clk_t,
  input  sio_i,
  output sio_o,
  output sio_t,
  input  ssn_i,
  output ssn_o,
  output ssn_t
);

// slave
modport s (
  output clk_i,
  input  clk_o,
  input  clk_t,
  output sio_i,
  input  sio_o,
  input  sio_t,
  output ssn_i,
  input  ssn_o,
  input  ssn_t
);

endinterface: spi_if
