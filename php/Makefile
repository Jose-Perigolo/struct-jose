.PHONY: inspect build test clean reset

inspect:
	@echo "PHP version:"
	@php --version | head -1
	@echo ""
	@echo "Project version:"
	@php -r "echo json_decode(file_get_contents('composer.json'))->version ?? 'unknown';" 2>/dev/null; echo ""

build:
	@echo "No build step for PHP"

test:
	vendor/bin/phpunit

clean:
	@echo "Nothing to clean"

reset: clean
	rm -rf vendor
