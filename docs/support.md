# Support

There is no implementation allowlist. A Lisp with usable CFFI and
Bordeaux Threads may attempt to load and run the library. Untested does not
mean blocked or unsupported.

## Verification

Verification requires the full suite, including native watching and scanning.
CI coverage describes actual automated tests, not assumed compatibility.

| Implementation | Linux | macOS | Windows |
|---|---|---|---|
| SBCL | Verified, CI (x86_64) | Verified, CI (ARM64) | Verified, CI (x86_64) |
| ECL | Verified, CI (x86_64) | Verified, CI (ARM64) | Untested |
| CCL | Verified, CI (x86_64) | Verified, CI (Intel)[^ccl-arm] | Untested |
| CLISP | Dependency failure, distro build | Untested | Untested |
| LispWorks | Untested | Untested | Untested |
| Allegro | Untested | Untested | Untested |

The [verification workflow](https://github.com/takeiteasy/trivial-watch/actions/runs/37839692440)
checks both native watching and scanning. Linux runs 102 checks, macOS 98,
and Windows 94; platform-specific cases account for the difference.
The runner prints versions, dependencies, architecture, and selected backend.

Local ARM64 macOS 15.7.5 checks also pass on SBCL 2.6.8, ECL 26.5.5,
and CCL 1.13 (v1.13-459-g690ff7ea). Snapshot reads use read-only descriptors on CCL.

## Running tests

```sh
tests/test.sh sbcl
tests/test.sh ecl
tests/test.sh ccl
tests/test.sh clisp
```

For another implementation, load `tests/run.lisp` using its batch mode.
The runner loads an existing Quicklisp environment or `~/quicklisp/setup.lisp`.
Set `QUICKLISP_SETUP` to use a different setup file. `WATCH_EXPECT_BACKEND`
asserts the selected backend, for example `inotify`.

## Limitations

| Combination | Coverage gap |
|---|---|
| LispWorks, Allegro | No licensed test installation available; untested and free to attempt loading. Verification remains pending in [ticket 6](https://todo.sr.ht/~takeiteasy/trivial-watch/6). |
| Ubuntu CLISP | The distro build lacks the threading support required by Bordeaux Threads: [verification ticket](https://todo.sr.ht/~takeiteasy/trivial-watch/10). |
| CCL, ECL on Windows | No working installation route in the selected CI setup; untested. |
| BSDs | No GitHub-hosted runner; native bindings remain in [ticket 3](https://todo.sr.ht/~takeiteasy/trivial-watch/3). |
| ABCL | Dedicated WatchService backend remains in [ticket 8](https://todo.sr.ht/~takeiteasy/trivial-watch/8). |
| JSCL | No filesystem or threading backend for this library. |

[^ccl-arm]: The local ARM64 CCL 1.13 build (v1.13-459-g690ff7ea) fails concurrent
    replacement tests. Distributed CCL 1.13 passes on Linux and Intel macOS.
    See [Limitations](#limitations) for the affected-build ticket.
