# Makefile - Common commands for Lua project

.PHONY: setup test clean

# Setup the environment
setup:
	chmod +x setup.sh
	./setup.sh

# Run tests
test:
	busted ./test/struct_test.lua

# Clean artifacts
clean:
	rm -rf luacov.* .busted
