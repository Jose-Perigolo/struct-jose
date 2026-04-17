.PHONY: build test clean vet fmt

build:
	go build ./...

test:
	go test -v ./...

vet:
	go vet ./...

fmt:
	go fmt ./...

clean:
	go clean ./...

all: fmt vet build test
