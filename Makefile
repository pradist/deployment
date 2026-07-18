ENV ?= dev

# Run all Hurl functional tests against the given env file
test:
	hurl tests/hurl/*.hurl --variables-file ./hurl/env/$(ENV).env --test

test-verbose:
	hurl tests/hurl/*.hurl --variables-file ./hurl/env/$(ENV).env --verbose
