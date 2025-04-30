# Makefile - Common commands for Lua project

.PHONY: setup test clean

# Setup the environment
setup:
	chmod +x setup.sh
	./setup.sh

# Run tests
test:
	find ./test/ -name "*test.lua" | xargs busted

# Clean artifacts
clean:
	rm -rf luacov.* .busted
