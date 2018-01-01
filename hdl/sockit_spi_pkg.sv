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

// serial data counter register
// 3 for 8 bits in a Byte and 12 for a 4KiB sized page
parameter int unsigned SCW = 3 + 12;

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Configuration/parameterization register                                    //
//                                                                            //
// Reset values of each bit in the configuration register are defined by the  //
// CFG_RST[31:0] parameter, another parameter CFG_MSK[31:0] defines which     //
// configuration field is read/write (mask=1) and which are read only, and    //
// fixed at the reset value (mask=0).                                         //
//                                                                            //
// Configuration register fields:                                             //
// [31:24] - sss - slave select selector                                      //
// [23:17] - sss - reserved (for configuring XIP for specific SPI devices)    //
// [   16] - end - bus endianness (0 - little, 1 - big) for XIP, DMA          //
// [15:11] - dly - SPI IO output to input switch delay (1 to 32 clk periods)  //
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
// Parameterization register fields:                                          //
// [ 7: 6] - ffo - clock domain crossing FIFO input  size                     //
// [ 5: 4] - ffo - clock domain crossing FIFO output size                     //
// [    3] - ??? - TODO                                                       //
// [ 2: 0] - ssn - number of slave select ports (from 1 to 8 signals)         //
//                                                                            //
// Slave select selector fields enable the use of each of up to 8 slave       //
// select signals, so that it is possible to enable more than one lave at the //
// same time (broadcast mode).                                                //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

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
  logic [SCW-1:0] cnt;  // transfer length counter
  logic [  2-1:0] iom;  // SPI IO mode (0 - 3wire, 1 - SPI, 2 - dual, 3 - quad)
  logic           die;  // data input  enable
  logic           doe;  // data output enable
  logic           sso;  // slave select output
  logic           cke;  // clock enable
} cmd_t;

endpackage: sockit_spi_pkg
