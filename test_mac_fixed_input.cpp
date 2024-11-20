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

    // get the data from the generated col_data_in and row_data_in using ifstream
    std::ifstream col_data_in("col_data_in.bins", std::ios::binary);
    if (!col_data_in) {
        std::cerr << "ERROR: could not open col_data_in.bins" << std::endl;
        exit(1);
    }
    std::ifstream row_data_in("row_data_in.bins", std::ios::binary);
    if (!row_data_in) {
        std::cerr << "ERROR: could not open row_data_in.bins" << std::endl;
        exit(1);
    }
    std::ifstream bypass_data_in("bypass_data_in.bins", std::ios::binary);
    if (!bypass_data_in) {
        std::cerr << "ERROR: could not open bypass_data_in.bins" << std::endl;
        exit(1);
    }
    //load gold row_data_out, col_data_out, psum_out using ifstream
    std::ifstream row_data_out("row_data_out_gold.bins", std::ios::binary);
    if (!row_data_out) {
        std::cerr << "ERROR: could not open row_data_out_gold.bins" << std::endl;
        exit(1);
    }
    std::ifstream col_data_out("col_data_out_gold.bins", std::ios::binary);
    if (!col_data_out) {
        std::cerr << "ERROR: could not open col_data_out_gold.bins" << std::endl;
        exit(1);
    }
    std::ifstream psum_out("psum_out_gold.bins", std::ios::binary);
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
            //load col_data_in, row_data_in, bypass_data_in using ifstream
            if (!col_data_in.eof()){
                col_data_in.read(reinterpret_cast<char*>(&dut->col_data_in), sizeof(dut->col_data_in));
            }
            if (!row_data_in.eof()){
                row_data_in.read(reinterpret_cast<char*>(&dut->row_data_in), sizeof(dut->row_data_in));
            }
            if (!bypass_data_in.eof()){
                bypass_data_in.read(reinterpret_cast<char*>(&dut->bypass_data_in), sizeof(dut->bypass_data_in));
            }

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
            
            // compare the generated row_data_out, col_data_out, psum_out with the gold row_data_out, col_data_out, psum_out using ifstream
            if (!row_data_out.eof()){
                uint8_t row_data_out_gold;
                row_data_out.read(reinterpret_cast<char*>(&row_data_out_gold), sizeof(row_data_out_gold));
                if (dut->row_data_out != row_data_out_gold){
                    std::cout << "ERROR: row_data_out mismatch at timestamp=" << timestamp << std::endl;
                    std::cout << "Expected: " << (int)row_data_out_gold << " Actual: " << (int)dut->row_data_out << std::endl;
                    exit(1);
                }
            }
            if (!col_data_out.eof()){
                uint8_t col_data_out_gold;
                col_data_out.read(reinterpret_cast<char*>(&col_data_out_gold), sizeof(col_data_out_gold));
                if (dut->col_data_out != col_data_out_gold){
                    std::cout << "ERROR: col_data_out mismatch at timestamp=" << timestamp << std::endl;
                    std::cout << "Expected: " << (int)col_data_out_gold << " Actual: " << (int)dut->col_data_out << std::endl;
                    exit(1);
                }
            }
            if (!psum_out.eof()){
                uint8_t psum_out_gold;
                psum_out.read(reinterpret_cast<char*>(&psum_out_gold), sizeof(psum_out_gold));
                if (dut->psum_out != psum_out_gold){
                    std::cout << "ERROR: psum_out mismatch at timestamp=" << timestamp << std::endl;
                    std::cout << "Expected: " << (int)psum_out_gold << " Actual: " << (int)dut->psum_out << std::endl;
                    exit(1);
                }
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
    std::cout << "Simulation of MAC PASSED" << std::endl;
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