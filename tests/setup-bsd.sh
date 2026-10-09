#!/bin/sh
set -eu
case "$(uname -s)" in
    FreeBSD)
        sudo pkg install -y sbcl curl
        lisp=sbcl
        ;;
    NetBSD)
        sudo pkgin -y install ecl curl
        lisp=ecl
        ;;
    OpenBSD)
        sudo pkg_add ecl curl
        lisp=ecl
        ;;
    *) exit 2 ;;
esac
curl -fsSL --retry 5 https://beta.quicklisp.org/quicklisp.lisp -o "$HOME/quicklisp.lisp"
case "$lisp" in
    sbcl) sbcl --non-interactive --load tests/install-quicklisp.lisp ;;
    ecl) ecl --norc --load tests/install-quicklisp.lisp ;;
esac
