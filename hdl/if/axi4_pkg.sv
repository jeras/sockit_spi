package axi4_pkg;

// convert AxLEN into integer burst length
function int unsigned LEN2int (logic [2:0] LEN);
  return (LEN+1);
endfunction: LEN2int

// convert integer burst length into AxLEN
function int unsigned int2LEN (int unsigned val);
  return (val-1);
endfunction: int2LEN


// convert AxSIZE into integer burst size
function int unsigned SIZE2int (logic [2:0] SIZE);
  return (1 << SIZE);
endfunction: SIZE2int

// convert integer burst size into AxSIZE
function int unsigned int2SIZE (int unsigned val);
  return ($clog2(val));
endfunction: int2SIZE

// enumeration of AxBURST modes
enum logic [1:0] {
  FIXED = 2'b00,
  INCR  = 2'b01,
  WRAP  = 2'b10
  //    = 2'b11  // reserved
} BURST;

// enumeration of xRESP modes
enum logic [1:0] {
  OKAY   = 2'b00,
  EXOKAY = 2'b01,
  SLVERR = 2'b10,
  DECERR = 2'b11
} RESP;

endpackage: axi4_pkg
