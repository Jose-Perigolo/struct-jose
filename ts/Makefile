.PHONY: inspect build test clean reset

inspect:
	@echo "Node.js version:"
	@node --version
	@echo ""
	@echo "Project version:"
	@node -p "require('./package.json').version"

build:
	npm run build

test:
	npm test

clean:
	rm -rf dist

reset: clean
	rm -rf node_modules
