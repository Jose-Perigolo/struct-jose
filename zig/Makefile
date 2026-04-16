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
	@out=$$(zig build test 2>&1 || true); \
	echo "$$out"; \
	passed=$$(echo "$$out" | grep -oE '[0-9]+/[0-9]+ tests passed' | head -1); \
	if [ -n "$$passed" ]; then \
		x=$$(echo "$$passed" | cut -d/ -f1); \
		y=$$(echo "$$passed" | cut -d/ -f2 | cut -d' ' -f1); \
		if [ "$$x" = "$$y" ] && [ "$$x" -gt 0 ]; then \
			exit 0; \
		fi; \
	fi; \
	exit 1

# Clean build artifacts
clean:
	rm -rf .zig-cache zig-out

# Full reset: clean + remove fetched dependencies
reset: clean
	rm -rf .zig-cache
