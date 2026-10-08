#!/bin/sh
# Usage: tests/test.sh [sbcl|ecl|ccl|clisp]
set -e
cd "$(dirname "$0")/.."
case "${1:-sbcl}" in
    sbcl) exec sbcl --non-interactive --no-userinit --load tests/run.lisp ;;
    ecl)  exec ecl --norc --load tests/run.lisp ;;
    ccl)  exec ccl --no-init --batch --load tests/run.lisp ;;
    clisp) exec clisp -q -norc tests/run.lisp ;;
    *) echo "unknown lisp: $1" >&2; exit 2 ;;
esac
