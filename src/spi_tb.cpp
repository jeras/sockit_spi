#include "Vspi.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

// global time variable
unsigned int n=0;
unsigned int t=0;

// global pointer to top module
Vspi* top;

// global trace file pointer
VerilatedVcdC* tfp;


// dump variables into VCD file and toggle clock
void clk_tgl () {
  tfp->dump (n++);
  top->clk_cpu = 0;
  top->clk_spi = 0;
  top->eval ();
  tfp->dump (n++);
  top->clk_cpu = 1;
  top->clk_spi = 1;
  top->eval ();
  t++;
}

void IOWR (int adr, int wdt) {
  top->reg_wen = 1;
  top->reg_adr = adr;
  top->reg_wdt = wdt;
  clk_tgl ();
  top->reg_wen = 0;
}

int  IORD (int adr) {
  int rdt;
  top->reg_ren = 1;
  top->reg_adr = adr;
  clk_tgl ();
  rdt = top->reg_rdt;
  top->reg_ren = 0;
  return (rdt);
}

int main(int argc, char **argv, char **env) {
  int i;
  int rdt;
  char mem [1024];
  Verilated::commandArgs(argc, argv);
  // init top verilog instance
  top = new Vspi;
  // init trace dump
  Verilated::traceEverOn(true);
  tfp = new VerilatedVcdC;
  top->trace (tfp, 99);
  tfp->open ("spi.vcd");
  // initialize simulation inputs
  top->clk_cpu = 1;
  top->rst_cpu = 1;
  top->clk_spi = 1;
  top->rst_spi = 1;
  // after two clock periods remove reset
  for (i=0; i<2; i++) clk_tgl ();
  top->rst     = 0;
  top->rst_spi = 0;
  for (i=0; i<2; i++) clk_tgl ();

  IOWR (2, 0x01ff0f84);  // write SPI configuration

  IOWR (0, 0x0b5a0000);  // write data register (command fast read)
  IOWR (1, 0x003f1012);  // write control register (enable a chip and start a 5+4 byte write+read)
  while (IORD (1) & 0x0000c000);
  rdt = IORD (0);        // read flash data

  // add dummy clock periods and end simulation
  for (i=0; i<4; i++) clk_tgl ();
  tfp->close();
  exit(0);
}

