#!/bin/sh
set -eu
prefix=${1:?Provide the installation directory}
build_dir=$(mktemp -d)
curl -fsSL --retry 5 https://ecl.common-lisp.dev/static/files/release/ecl-26.5.5.tgz -o "$build_dir/ecl.tgz"
test "$(sha256 -q "$build_dir/ecl.tgz")" = a01a5bcda8c5b73e59dda3494fd13e5fec5db6aa1dad782c3cc3bb57f1633435
tar -xzf "$build_dir/ecl.tgz" -C "$build_dir"
cd "$build_dir/ecl-26.5.5"
./configure --prefix="$prefix" --enable-threads=yes --enable-boehm=system --enable-gmp=system \
            --with-libgc-prefix=/usr/pkg --with-gmp-prefix=/usr/pkg --with-libffi-prefix=/usr/pkg
make -j2
make install
