#!/bin/sh
# Usage: tests/test.sh [sbcl|ecl|ccl|clisp|abcl]
set -e
cd "$(dirname "$0")/.."
if [ "${1:-sbcl}" != abcl ]; then
    case "$(uname -s)" in
        Darwin|FreeBSD|NetBSD|OpenBSD)
            abi_dir=$(mktemp -d)
            cc -Wall -Wextra -Werror tests/kqueue-abi.c -o "$abi_dir/probe"
            export KQUEUE_ABI_FILE="$abi_dir/abi.lisp"
            "$abi_dir/probe" > "$KQUEUE_ABI_FILE"
            ;;
    esac
fi
case "${1:-sbcl}" in
    sbcl) exec sbcl --non-interactive --no-userinit --load tests/run.lisp ;;
    ecl)  exec ecl --norc --load tests/run.lisp ;;
    ccl)  exec ccl --no-init --batch --load tests/run.lisp ;;
    clisp) exec clisp -q -norc tests/run.lisp ;;
    abcl) exec java -jar "${ABCL_JAR:?Set ABCL_JAR to abcl.jar}" --noinit --batch --load tests/run.lisp ;;
    *) echo "unknown lisp: $1" >&2; exit 2 ;;
esac
