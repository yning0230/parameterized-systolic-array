// DESCRIPTION:  simulation of mac 
//======================================================================
#include <iostream>
#include <stdint.h> 
#include <fstream> 
#include <cstdlib>
#include <ctime>



// Include common routines
#include <verilated.h>
// Include model header, generated from Verilating "mac.v"
#include "Vmac.h"
#include "Vmac__Syms.h"

#ifdef VCD_OUTPUT
#include <verilated_vcd_c.h>
#endif

#define RUN_CYCLES 100

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
    Vmac* dut = new Vmac();

    // store the generated col_data_in and row_data_in using ofstream
    std::ofstream col_data_in("col_data_in.bins", std::ios::binary);
    if (!col_data_in) {
        std::cerr << "ERROR: could not open col_data_in.bins" << std::endl;
        exit(1);
    }
    std::ofstream row_data_in("row_data_in.bins", std::ios::binary);
    if (!row_data_in) {
        std::cerr << "ERROR: could not open row_data_in.bins" << std::endl;
        exit(1);
    }
    std::ofstream bypass_data_in("bypass_data_in.bins", std::ios::binary);
    if (!bypass_data_in) {
        std::cerr << "ERROR: could not open bypass_data_in.bins" << std::endl;
        exit(1);
    }
    //store row_data_out, col_data_out, psum_out using ofstream
    std::ofstream row_data_out("row_data_out_gold.bins", std::ios::binary);
    if (!row_data_out) {
        std::cerr << "ERROR: could not open row_data_out_gold.bins" << std::endl;
        exit(1);
    }
    std::ofstream col_data_out("col_data_out_gold.bins", std::ios::binary);
    if (!col_data_out) {
        std::cerr << "ERROR: could not open col_data_out_gold.bins" << std::endl;
        exit(1);
    }
    std::ofstream psum_out("psum_out_gold.bins", std::ios::binary);
    if (!psum_out) {
        std::cerr << "ERROR: could not open psum_out_gold.bins" << std::endl;
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
            // generate random data for col_data_in and row_data_in
            uint8_t col_data_in_rand = rand() % 12;
            uint8_t row_data_in_rand = rand() % 12;
            uint8_t bypass_data_in_rand = rand() % 12;

            dut -> col_data_in = col_data_in_rand;
            dut -> row_data_in = row_data_in_rand;
            dut -> bypass_data_in = bypass_data_in_rand;

            if (timestamp % 12 == 0 && timestamp > RESET_TIME){
                dut -> rst_accumulator = 1;
            }
            else if (timestamp % 12 == 1 && timestamp > RESET_TIME){
                dut -> bypass_en = 1;
            }
            else{
                dut -> rst_accumulator = 0;
                dut -> bypass_en = 0;
            }

            // store the generated col_data_in and row_data_in using ofstream
            col_data_in.write((reinterpret_cast<char*>(&col_data_in_rand)), sizeof(col_data_in_rand));
            row_data_in.write((reinterpret_cast<char*>(&row_data_in_rand)), sizeof(row_data_in_rand));
            bypass_data_in.write((reinterpret_cast<char*>(&bypass_data_in_rand)), sizeof(bypass_data_in_rand));
            

            // store row_data_out, col_data_out, psum_out using ofstream
            row_data_out.write(reinterpret_cast<char*>(&dut->row_data_out), sizeof(dut->row_data_out));
            col_data_out.write(reinterpret_cast<char*>(&dut->col_data_out), sizeof(dut->col_data_out));
            psum_out.write(reinterpret_cast<char*>(&dut->psum_out), sizeof(dut->psum_out));

            std::cout << "timestamp=" << timestamp << " col_data_in=" << (int)dut->col_data_in << " row_data_in=" << (int)dut->row_data_in << " bypass_data_in=" << (int)dut->bypass_data_in << " row_data_out=" << (int)dut->row_data_out << " col_data_out=" << (int)dut->col_data_out << " psum_out=" << (int)dut->psum_out << std::endl;

            timestamp_WB = timestamp - RESET_TIME;            
        }


    #ifdef VCD_OUTPUT
        trace->dump(timestamp);
    #endif
        ++timestamp;
    }

#ifdef DPRINTF
    std::cout << "Cycles=" << (timestamp_WB / 2) << std::endl; 
#endif

    // Final model cleanup
    dut->final();

#ifdef VCD_OUTPUT
    trace->close();
    delete trace;
#endif

    // Destroy DUT
    delete dut;
    // close files
    col_data_in.close();
    row_data_in.close();
    bypass_data_in.close();
    row_data_out.close();
    col_data_out.close();
    psum_out.close();
    // Fin
    exit(0);
}