#!/bin/bash

# pacboy -S zip: unzip: p7zip: gcc:i
# gem install redcarpet

set -e

[[ "$MSYSTEM" == "MINGW32" ]] || { echo "Run this script from within the MinGW32@MSYS2 shell"; exit 1; }

version=0.2.0
release=1

tag=mclone-$version-win32-$release

sha256sum -c sha256 || { echo "Integrity check failed"; exit 1; }

root=$(pwd)
dist=$root/dist
cache=$root/cache

rm -rf "$dist"
mkdir -p "$dist"/{bin,doc}

cp ../*.md "$dist"/doc

gcc -O2 -DNDEBUG -s -o "$dist"/bin/mclone.exe mclone.c

ruby ../md2html.rb ../README.md "$dist"/doc/README.html

gem build mclone.gemspec

(
	cd "$dist"
	7z x "$cache"/rubyinstaller-*x86.7z
	mv rubyinstaller-* ruby
	unzip -o "$cache"/rclone-*.zip
	mv rclone-* rclone
)

(
	cd "$dist/ruby"
	cmd /c "bin\\gem install ../../../mclone-$version.gem"
	rm -rf include packages share ridk_use lib/*.a lib/pkgconfig lib/ruby/gems/*/cache/*
	cd "$dist"/rclone
	find -not -name '*.exe' -and -type f -exec rm -rf {} \;
)

echo "
	#define MyAppVersion \"$version-$release\"
	#define MySetup \"$tag\"
" > mclone.auto.inc

start mclone.iss # This requires .iss to be properly registered

#