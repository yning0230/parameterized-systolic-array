// DESCRIPTION:  simulation of ctrl 
//======================================================================
#include <iostream>
#include <stdint.h>
#include <fstream> 
#include <cstdlib>
#include <ctime>

// Include common routines
#include <verilated.h>
// Include model header, generated from Verilating "ctrl.v"
#include "Vctrl.h"
#include "Vctrl__Syms.h"

#ifdef VCD_OUTPUT
#include <verilated_vcd_c.h>
#endif

#define RUN_CYCLES 1000

#define CLOCK_PERIOD 2

#define RESET_TIME  10

// Current simulation time (64-bit unsigned)
uint64_t timestamp = 0;

double sc_time_stamp() { 
  return timestamp;
}

int main(int argc, char** argv, char** env) {
    // turn off unused variable warnings
    if (0 && argc && argv && env) {}

    // Construct the Verilated model
    Vctrl* dut = new Vctrl();

    //load the gold bypass_en and rst_accumulator using ifstream
    std::ifstream bypass_en_gold("bypass_en_gold.bins", std::ios::binary);
    if (!bypass_en_gold) {
        std::cerr << "ERROR: could not open bypass_en_gold.bins" << std::endl;
        exit(1);
    }
    std::ifstream rst_accumulator_gold("rst_accumulator_gold.bins", std::ios::binary);
    if (!rst_accumulator_gold) {
        std::cerr << "ERROR: could not open rst_accumulator_gold.bins" << std::endl;
        exit(1);
    }

#ifdef VCD_OUTPUT
    Verilated::traceEverOn(true);
    auto trace = new VerilatedVcdC();
    dut->trace(trace, 2999);
    trace->open("trace.vcd");
#endif

#ifdef DPRINTF
    uint64_t timestamp_WB = 0;
#endif

    dut->clk = 0;
    dut->rst = 0;

    while (timestamp < RUN_CYCLES) {      
        bool clk_transition = (timestamp % CLOCK_PERIOD) == 0;
        if (clk_transition) 
            dut->clk = !dut->clk; 

        if (timestamp > 1 && timestamp < RESET_TIME) {
            dut->rst = 1;  // Assert reset
        } else {
            dut->rst = 0;  // Deassert reset
        }
        
        // Evaluate model
        dut->eval();

        // Verilator allows to access verilator public data structure
        if (clk_transition && dut->clk) {
            uint8_t bypass_en = dut ->bypass_en;
            uint8_t rst_accumulator = dut ->rst_accumulator;
            //load the gold bypass_en and rst_accumulator using ifstream
            uint8_t bypass_en_gold_read;
            uint8_t rst_accumulator_gold_read;
            bypass_en_gold.read(reinterpret_cast<char*>(&bypass_en_gold_read), sizeof(bypass_en_gold_read));
            rst_accumulator_gold.read(reinterpret_cast<char*>(&rst_accumulator_gold_read), sizeof(rst_accumulator_gold_read));
            //compare the gold bypass_en and rst_accumulator with the dut bypass_en and rst_accumulator
            if (bypass_en_gold_read != bypass_en){
                std::cout << "ERROR: bypass_en_gold_read != bypass_en" << std::endl;
                exit(1);
            }
            if (rst_accumulator_gold_read != rst_accumulator){
                std::cout << "ERROR: rst_accumulator_gold_read != rst_accumulator" << std::endl;
                exit(1);
            }

            timestamp_WB = timestamp - RESET_TIME;            
        }


    #ifdef VCD_OUTPUT
        trace->dump(timestamp);
    #endif
        ++timestamp;
    }

#ifdef DPRINTF
    std::cout << "Cycles=" << (timestamp_WB / 2) << std::endl; 
    std::cout << "Simulation of ctrl PASSED" << std::endl;
#endif

    // Final model cleanup
    dut->final();

#ifdef VCD_OUTPUT
    trace->close();
    delete trace;
#endif

    // Destroy DUT
    delete dut;
    // Close files
    bypass_en_gold.close();
    rst_accumulator_gold.close();
    // Fin
    exit(0);
}