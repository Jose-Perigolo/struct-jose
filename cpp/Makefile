compile_and_run_tests:
	g++ tests/test_voxgig_struct.cpp -Werror --std=c++11 -I ~/Project/json/include -o out.out && ./out.out

check_leak:
	valgrind -s ./out.out
