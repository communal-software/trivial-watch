# CI

GitHub Actions tests platform event sources and scanning on Linux, macOS, Windows,
FreeBSD, NetBSD and OpenBSD.
The configured implementation/OS pairs live in
[`.github/ci-matrix.json`](../.github/ci-matrix.json).

| Trigger | Coverage |
|---|---|
| Code push to `trunk` or pull request | Full verified matrix |
| Docs-only change | None |
| Manual dispatch | Filter by Lisp and OS; select CLISP for source-build verification or clisp-distro for the distro diagnostic |

Jobs assert the selected backend and print implementation, OS, architecture, and
dependency versions. Failed jobs fail the workflow; newer pushes cancel older
runs for the same branch or pull request.

```sh
gh workflow run ci.yml -f lisp=ecl -f os=macos
```

## Platform jobs

| Platform | Lisp | Setup |
|---|---|---|
| Linux, macOS, Windows | Existing SBCL/ECL/CCL pairs | Roswell |
| Linux, macOS, Windows | ABCL 1.9.2 | Downloaded JAR, Temurin Java 17 |
| FreeBSD 15.1 | SBCL | BSD VM, packages |
| NetBSD 11.0, OpenBSD 7.9 | ECL | BSD VM, packages |
| Ubuntu 24.04 | Threaded CLISP | Pinned source build; manual verification |

BSD jobs use the pinned `cross-platform-actions` v1.6.0 release on Ubuntu hosts.
Each guest checks threading, compares CFFI bindings with a C header probe, then
runs the full suite with `WATCH_EXPECT_BACKEND=kqueue`. Other architectures remain
unverified.

SBCL and ECL macOS jobs use ARM64 runners; distributed CCL uses Intel.
Fresh-process core checks verify that backend extensions do not load CFFI.
ABCL jobs load the WatchService backend without native bindings.

## CLISP verification

The `clisp` selector builds upstream revision
`e63399e8d7bc69a911dd782846256adf80a5439a` with POSIX threads and FFI. The
installation cache key includes the revision, build script and runner identity.
The job checks `:mt` and dependencies before native and scan tests.

```sh
gh workflow run ci.yml -f lisp=clisp -f os=linux
gh workflow run ci.yml -f lisp=clisp-distro -f os=linux
gh workflow run ci.yml -f lisp=ecl -f os=netbsd
```

The distro diagnostic retains the expected dependency failure. Source-built CLISP
remains outside the ordinary matrix until verification succeeds. See
[Support limitations](support.md#limitations) for its verification status.

[`.build.yml`](../.build.yml) also tests SBCL/Linux on sourcehut pushes.
Run `tests/test.sh sbcl` locally before pushing.

## Distribution releases

Version tags publish to [takeiteasy's Quicklisp dist](https://github.com/takeiteasy/ql-dist).
The tag matches the ASDF version, for example `v0.1.0`.
[The notifier workflow](../.github/workflows/ql-dist.yml) uses the repository
secret `QL_DIST_TOKEN` to request a distribution build.
