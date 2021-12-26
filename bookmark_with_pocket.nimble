# Package

version = "0.1.0"
author = "last_arg"
description = "Browser extension that adds bookmark to Pocket if rules allow it"
license = "MIT"
srcDir = "src"
binDir = "dist"
bin = @["bookmark_with_pocket"]
skipDirs = @["balls"]

# backend = "js"

# Dependencies
requires "nim >= 1.6.0"
requires "nodejs >= 16.10.0"
requires "fusion >= 1.1"
requires "https://github.com/disruptek/badresults >= 2.1.0"

# Development dependency
requires "https://github.com/disruptek/balls >= 3.0.0"
requires "halonium >= 0.2.6"
