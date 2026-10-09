#!/bin/sh
set -eu
prefix=${1:?Provide the installation directory}
revision=e63399e8d7bc69a911dd782846256adf80a5439a
if [ ! -x "$prefix/bin/clisp" ]; then
    build_dir=$(mktemp -d)
    curl -fsSL --retry 5 "https://gitlab.com/gnu-clisp/clisp/-/archive/$revision/clisp-$revision.tar.gz" -o "$build_dir/source.tar.gz"
    tar -xzf "$build_dir/source.tar.gz" -C "$build_dir"
    cd "$build_dir/clisp-$revision"
    ./configure --prefix="$prefix" --with-threads=POSIX_THREADS --with-ffcall build
    make -C build
    # Timed prompt tests need an open input stream rather than immediate EOF.
    mkfifo "$build_dir/check-input"
    exec 3<> "$build_dir/check-input"
    make -C build check < "$build_dir/check-input"
    exec 3>&-
    make -C build install
fi
"$prefix/bin/clisp" -q -norc -x '(assert (member :mt *features*))'
