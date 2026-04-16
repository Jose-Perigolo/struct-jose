.PHONY: inspect build test clean reset

inspect:
	@echo "Node.js version:"
	@node --version
	@echo ""
	@echo "Project version:"
	@node -p "require('./package.json').version"

build:
	@echo "No build step for JS"

test:
	npm test

clean:
	@echo "Nothing to clean"

reset: clean
	rm -rf node_modules
