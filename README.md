# parameterized-systolic-array
Initial setup:

```bash
    source init.sh
```

The systolic array is reconfigurable with dimensions using `ROWS`, `K`, and `COLS`. Example usage:
```bash
    make ROWS=3 K=4 COLS=5 NUM_TESTS=10 SEED=2 systolic_array
```

The above command generates an array to process a $3\times4$ matrix multiplied by a $4\times 5$ matrix. The test bench would generate 10 random matrices with a random seed. The results would be available inside the log file `results.log`.

The code has been tested out working for the below test cases to cover full range of ROWS, K, and COLS combinations:
```bash
        make systolic_array ROWS=128 COLS=2 K=8 NUM_TESTS=100
	make systolic_array ROWS=128 COLS=8 K=2 NUM_TESTS=100
	make systolic_array ROWS=128 COLS=20 K=20 NUM_TESTS=100
	make systolic_array ROWS=10 COLS=128 K=2 NUM_TESTS=100
	make systolic_array ROWS=10 COLS=2 K=128 NUM_TESTS=100
```

How it works:
	each row of one input propagates from the left of the array to the right.
	each column of the other input propagates from the top of the array to the bottom.
	The output of each MAC unit is passed to the left MAC unit whenever it becomes a completely ready element for the output. 
	The final output for each row can then be collected sequentially from the leftmost column of the MAC units.

Key Challenges:
Because psum need C cycles to be popped out, while calculation need K cycles to be completed. This asynchrony will cause problem:
When K > C, there will be “0” bubbles in the output, as there will be time when no psum can be popped out.
When K < C, some psum results are ready but cannot be popped out. It will stuck in FIFO and finally cause overflow.

Solutions:
Use AXI stream to control dataflow.
psum_out_valid control to eliminate zero bubbles in between input datasets
Stall control of input and intermediate states when output fifo is approaching half-full.

