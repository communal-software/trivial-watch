#!/bin/sh
set -eu
case "$(uname -s)" in
    FreeBSD)
        sudo pkg install -y sbcl curl
        lisp=sbcl
        ;;
    NetBSD)
        sudo pkgin -y install ecl curl gmake
        if ! ecl --norc --eval '(assert (member :threads *features*))' --eval '(quit)'; then
            sudo pkg_delete ecl
            sh tests/build-ecl.sh "$HOME/threaded-ecl"
            export PATH="$HOME/threaded-ecl/bin:$PATH"
        fi
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
if [ "$(uname -s)" = NetBSD ] && [ -x "$HOME/threaded-ecl/bin/ecl" ]; then
    printf '%s\n' "$HOME/threaded-ecl/bin" > "$HOME/.trivial-watch-lisp-path"
fi
