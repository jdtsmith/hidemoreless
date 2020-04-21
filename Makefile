FILES = hidemoreless_loader.rb hidemoreless/hml_core.rb

all: hidemoreless.rbz

hidemoreless.rbz: $(FILES)
	zip -r -X $@ $(FILES)
