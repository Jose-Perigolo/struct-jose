.PHONY: inspect build test clean reset

inspect:
	@echo "Python version:"
	@python3 --version
	@echo ""
	@echo "Project version:"
	@python3 -c "import voxgig_struct; print(getattr(voxgig_struct, '__version__', 'unknown'))" 2>/dev/null || echo "unknown"

build:
	@echo "No build step for Python"

test:
	python3 -m unittest discover -s tests

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	rm -rf *.egg-info dist build

reset: clean
