////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  package containning type definitions                                      //
//                                                                            //
//  Copyright (C) 2008-2011  Iztok Jeras                                      //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

package sockit_spi_pkg;

// number of slave select signals
parameter int unsigned SSW = 8;

// serial data register width
parameter int unsigned SDW = 8;
// serial data register width logarithm
parameter int unsigned SDL = 3;

// SPI configuration
typedef struct packed {
  logic [SSW-1:0] sss;  // slave select selector
  logic [ 19-1:0] rsv;  // reserved
  logic           dir;  // shift direction (0 - LSB first, 1 - MSB first)
  logic           soe;  // slave select output enable
  logic           coe;  // clock output enable
  logic           pha;  // clock phase
  logic           pol;  // clock polarity
} cfg_t;

// SPI command
typedef struct packed {
  logic [SDL-1:0] cnt;  // transfer length counter
  logic           lst;  // last
  logic [  2-1:0] iom;  // SPI IO mode (0 - 3wire, 1 - SPI, 2 - dual, 3 - quad)
  logic           die;  // data input  enable
  logic           doe;  // data output enable
  logic           sso;  // slave select output
  logic           cke;  // clock enable
} cmd_t;

endpackage: sockit_spi_pkg
