rm -rf 01.txt 02.txt 03.txt 04.txt 05.txt 06.txt 07.txt 08.txt 09.txt 10.txt 11.txt 12.txt 13.txt 14.txt

	make systolic_array ROWS=128 COLS=2 K=8 NUM_TESTS=100
	cat results.log | grep PASSED >> 01.txt

	make systolic_array ROWS=128 COLS=8 K=2 NUM_TESTS=100
	cat results.log | grep PASSED >> 02.txt

	make systolic_array ROWS=128 COLS=20 K=20 NUM_TESTS=100
	cat results.log | grep PASSED >> 03.txt

	make systolic_array ROWS=10 COLS=128 K=2 NUM_TESTS=100
	cat results.log | grep PASSED >> 04.txt

	make systolic_array ROWS=10 COLS=2 K=128 NUM_TESTS=100
	cat results.log | grep PASSED >> 05.txt

