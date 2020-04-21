FILES = hidemoreless_loader.rb hidemoreless/hml_core.rb
VERSION := $(shell git describe --tags --abbrev=0)

TARG := hidemoreless_$(VERSION).rbz

$(TARG): $(FILES)
	zip -r -X $@ $(FILES)
