# Support

There is no implementation allowlist. A Lisp with usable CFFI and
Bordeaux Threads may attempt to load and run the library. Untested does not
mean blocked or unsupported.

## Verification

Verification requires the full suite, including native watching and scanning.
CI coverage describes actual automated tests, not assumed compatibility.

| Implementation | Linux | macOS | Windows |
|---|---|---|---|
| SBCL | Pending CI | Verified locally, ARM64 | Pending CI |
| ECL | Pending CI | Verified locally, ARM64 | Untested |
| CCL | Pending CI | Verification failure, local ARM64 build; Intel pending | Untested |
| CLISP | Pending verification | Untested | Untested |
| LispWorks | Untested | Untested | Untested |
| Allegro | Untested | Untested | Untested |

Local checks use SBCL 2.6.8, ECL 26.5.5, and CCL 1.13
(v1.13-459-g690ff7ea), on ARM64 macOS 15.7.5. SBCL and ECL pass 80 checks.
The runner prints versions, dependencies, architecture, and selected backend.

## Running tests

```sh
tests/test.sh sbcl
tests/test.sh ecl
tests/test.sh ccl
tests/test.sh clisp
```

For another implementation, load `tests/run.lisp` using its batch mode.
The runner loads an existing Quicklisp environment or `~/quicklisp/setup.lisp`.
Set `QUICKLISP_SETUP` to use a different setup file. `NOTIFY_EXPECT_BACKEND`
asserts the selected backend, for example `inotify`.

## Limitations

| Combination | Coverage gap |
|---|---|
| LispWorks, Allegro | No licensed test installation available; untested and free to attempt loading. Verification remains pending in [ticket 6](https://todo.sr.ht/~takeiteasy/trivial-notify/6). |
| CCL, ECL on Windows | No working installation route in the selected CI setup; untested. |
| BSDs | No GitHub-hosted runner; native bindings remain in [ticket 3](https://todo.sr.ht/~takeiteasy/trivial-notify/3). |
| ABCL | Dedicated WatchService backend remains in [ticket 8](https://todo.sr.ht/~takeiteasy/trivial-notify/8). |
| JSCL | No filesystem or threading backend for this library. |
