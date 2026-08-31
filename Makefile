.PHONY: test build clean

test:
	./scripts/run-tests.sh

build: test
	./scripts/build-app.sh

clean:
	rm -rf .build dist
