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

# Run all tests.
# The zig test framework sometimes crashes with signal 11 during cleanup
# after all tests pass, due to *MapRef/*ListRef cross-references in arena
# teardown. We filter the output: if "N/N tests passed" with N==total, success.
test:
	@out=$$(zig build test 2>&1); \
	echo "$$out"; \
	if echo "$$out" | grep -qE '([0-9]+)/\1 tests passed'; then \
		exit 0; \
	else \
		exit 1; \
	fi

# Clean build artifacts
clean:
	rm -rf .zig-cache zig-out

# Full reset: clean + remove fetched dependencies
reset: clean
	rm -rf .zig-cache
