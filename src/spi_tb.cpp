#include "Vspi.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

unsigned int t=0;

void clk_tgl (Vspi* top, VerilatedVcdC* tfp) {
  for (int clk=0; clk<2; clk++) {
    tfp->dump (2*t+clk);
    top->clk     = !top->clk    ;
    top->clk_spi = !top->clk_spi;
    top->eval ();
  }
  t++;
}

void IOWR32 (int adr, int wdt) {
}

int  IORD32 (int adr) {
}

int main(int argc, char **argv, char **env) {
  int i;
  int clk;
  Verilated::commandArgs(argc, argv);
  // init top verilog instance
  Vspi* top = new Vspi;
  // init trace dump
  Verilated::traceEverOn(true);
  VerilatedVcdC* tfp = new VerilatedVcdC;
  top->trace (tfp, 99);
  tfp->open ("spi.vcd");
  // initialize simulation inputs
  top->clk     = 1;
  top->rst     = 1;
  top->clk_spi = 1;
  top->rst_spi = 1;
  // run simulation for 100 clock periods
  for (i=0; i<20; i++) {
    top->rst     = (i < 2);
    top->rst_spi = (i < 2);
    // dump variables into VCD file and toggle clock
    clk_tgl (top, tfp);
    if (Verilated::gotFinish())  exit(0);
  }
  tfp->close();
  exit(0);
}

