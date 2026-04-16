.PHONY: inspect build test clean reset

# Inspect: show language and project version info
inspect:
	@echo "Zig version:"
	@zig version
	@echo ""
	@echo "Project version:"
	@grep '.version' build.zig.zon | head -1 | sed 's/.*"\(.*\)".*/\1/'

# Build the library
build:
	zig build

# Run all tests
test:
	zig build test

# Clean build artifacts
clean:
	rm -rf .zig-cache zig-out

# Full reset: clean + remove fetched dependencies
reset: clean
	rm -rf .zig-cache
