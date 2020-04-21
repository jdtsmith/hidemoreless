require "sketchup.rb"
require "extensions.rb"

# Load plugin as extension (so that user can disable it)

loader = SketchupExtension.new "HideMoreLess","hidemoreless/hml_core.rb"
loader.copyright= "Copyright 2020"
loader.creator= "J.D. Smith"
loader.version = "0.5"
loader.description = "Selective heirarchy-based hider tool"
Sketchup.register_extension loader, true
