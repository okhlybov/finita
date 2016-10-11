#!/bin/bash

# 1) Put Ruby runtime .7z archive into ext/ directory (Refer to http://rubyinstaller.org/downloads/)
# 2) Install the Inno Setup 5+ into the Program Files directory (Refer to http://www.jrsoftware.org/isdl.php)
# 3) Run this script from within Cygwin

set -e

rm -rf dist

mkdir -p dist/{bin,lib,sample}

cp ../bin/finitac dist/bin

cp finitac.cmd dist/bin

cp -R ../lib dist

7z x ext/ruby-*.7z -odist

(cd dist && mv ruby* ruby)

cp -n ext/*.pem dist/ruby/lib/ruby/2.*/rubygems/ssl_certs # Refer to http://guides.rubygems.org/ssl-certificate-update/

gem=dist/ruby/bin/gem.cmd
gem_cmd=`cygpath -wa $gem`
chmod -R +rwx dist/ruby/*
cmd.exe /c "$gem_cmd" install autoc

cp ../sample/*.{c,rb} dist/sample

ver=`date +'%Y%m%d'`

f=dist/lib/finita/common.rb
sed "s/.*Version.*/Version=\"$ver\"/" $f > t && mv t $f

f=finita.iss
sed "s/.*#define.*MyAppVersion.*/#define MyAppVersion \"$ver\"/" $f > _$f
isc=`cygpath -wa "$PROGRAMFILES/Inno Setup 5/compil32.exe"`
cmd /c "$isc" /cc _$f
rm _$f

#