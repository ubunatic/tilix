.PHONY: ⚙️ 🤖  # ⚙️ = manual/once, 🤖 = managed

BINARY := tilix
BINARY_SUFFIX := -latest
PREFIX := $(HOME)/.local/bin

_prim := \033[36m
_rst  := \033[0m

help: 🤖  # show this help
	@grep -E '^[a-zA-Z_-]+:.*[⚙🤖].*#+' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*#+ "}; {printf "    $(_prim)%-15s$(_rst) %s\n", $$1, $$2}'

build: ⚙️  # build the binary
	dub build --build=release --compiler=ldc2

test: ⚙️  # run all tests
  # TODO: add test commands here

install: ⚙️ build  # install tilix
	cp $(BINARY) $(PREFIX)/$(BINARY)$(BINARY_SUFFIX)

uninstall: ⚙️  # uninstall tilix
	rm -f $(PREFIX)/$(BINARY)$(BINARY_SUFFIX)

clean: ⚙️  # remove build output
	rm -f $(BINARY)

test-q1: 🤖  # run tests under Quota-1 enforcement
	harnez exec --quota-1 -- $(MAKE) test
