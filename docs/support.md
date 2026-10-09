# Support

There is no implementation allowlist. Native backends require CFFI; ABCL uses
Java WatchService. The core requires a filesystem API and Bordeaux Threads. Untested does not
mean blocked or unsupported.

## Verification

Verification requires the full suite, including native watching and scanning.
CI coverage describes actual automated tests, not assumed compatibility.

| Implementation | Linux | macOS | Windows |
|---|---|---|---|
| SBCL | Verified, CI (x86_64) | Verified, CI (ARM64) | Verified, CI (x86_64) |
| ECL | Verified, CI (x86_64) | Verified, CI (ARM64) | Untested |
| CCL | Verified, CI (x86_64) | Verified, CI (Intel)[^ccl-arm] | Untested |
| ABCL 1.9.2 | Verified, CI (x86_64) | Verified, CI (ARM64) | Verified, CI (x86_64) |
| CLISP | Verified, CI (x86_64), threaded source[^clisp] | Untested | Untested |
| LispWorks | Untested | Untested | Untested |
| Allegro | Untested | Untested | Untested |

The [verification workflow](https://github.com/takeiteasy/trivial-watch/actions/runs/37925890098)
checks both native watching and scanning. Platform-specific cases account for differences in check counts.
The runner prints versions, dependencies, architecture, and selected backend.

Local ARM64 macOS 15.7.5 checks also pass on SBCL 2.6.8, ECL 26.5.5,
and CCL 1.13 (v1.13-459-g690ff7ea). Snapshot reads use read-only descriptors on CCL.

BSD verification covers these x86-64 configurations:

| Platform | Implementation | Backend |
|---|---|---|
| FreeBSD 15.1 | SBCL 2.6.6 | kqueue |
| NetBSD 11.0 | ECL 26.5.5, threaded source | kqueue |
| OpenBSD 7.9 | ECL 24.5.10 | kqueue |

## Running tests

```sh
tests/test.sh sbcl
tests/test.sh ecl
tests/test.sh ccl
tests/test.sh clisp
ABCL_JAR=/path/to/abcl.jar tests/test.sh abcl
```

For another implementation, load `tests/run.lisp` using its batch mode.
The runner loads an existing Quicklisp environment or `~/quicklisp/setup.lisp`.
Set `QUICKLISP_SETUP` to use a different setup file. `WATCH_EXPECT_BACKEND`
asserts the selected backend, for example `inotify`. On kqueue platforms the shell
runner compiles an ABI probe against system headers. Direct Lisp launches use
`KQUEUE_ABI_FILE` to point at the probe output.

Run the CFFI-free core check in a fresh Lisp process:

```sh
sbcl --non-interactive --load tests/core.lisp
```

## Limitations

| Combination | Coverage gap |
|---|---|
| LispWorks, Allegro | No licensed test installation available; untested and free to attempt loading. Verification remains pending in [ticket 6](https://todo.sr.ht/~takeiteasy/trivial-watch/6). |
| Ubuntu CLISP | The distro build lacks the threading support required by Bordeaux Threads: [verification ticket](https://todo.sr.ht/~takeiteasy/trivial-watch/10). |
| CCL, ECL on Windows | No working installation route in the selected CI setup; untested. |
| Other BSD implementations and architectures | Untested; the verified combinations are documented in [ticket 3](https://todo.sr.ht/~takeiteasy/trivial-watch/3). |
| NetBSD before 11 | Uses scanning; the older native ABI needs separate verification in [ticket 12](https://todo.sr.ht/~takeiteasy/trivial-watch/12). |
| JSCL | No filesystem or threading backend for this library. |

[^ccl-arm]: Distributed CCL macOS CI uses Intel runners. ARM64 CCL is verified
    locally; snapshot reads bypass CCL's pathname stream probes.

[^clisp]: CI builds pinned upstream CLISP with POSIX threads and FFI. Snapshot
    reads use CLISP's built-in FFI without changing duplicate-open settings.
    The CFFI-free core check runs in a fresh process.
    [CLISP verification](https://github.com/takeiteasy/trivial-watch/actions/runs/37925938482)
    covers native and scan behavior.
