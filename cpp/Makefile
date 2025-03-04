compile_and_run_tests:
	g++ tests/test_voxgig_struct.cpp -Werror --std=c++11 -I ./src -I ./tests -I ~/Project/json/include -o out.out && ./out.out

check_leak:
	valgrind --leak-check=full --show-leak-kinds=all ./out.out
