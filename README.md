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
