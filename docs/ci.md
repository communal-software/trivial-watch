# CI

GitHub Actions verifies native watching and scanning on Linux, macOS, and Windows.
The configured implementation/OS pairs live in
[`.github/ci-matrix.json`](../.github/ci-matrix.json).

| Trigger | Coverage |
|---|---|
| Code push to `trunk` or pull request | Full verified matrix |
| Docs-only change | None |
| Manual dispatch | Filter by Lisp and OS family; explicitly select CLISP for its verification job |

Jobs assert the native backend and print implementation, OS, architecture, and
dependency versions. Failures are required checks; newer pushes cancel older
runs for the same branch or pull request.

```sh
gh workflow run ci.yml -f lisp=ecl -f os=macos
```

SBCL and ECL macOS jobs use ARM64 runners. Distributed CCL macOS builds use an
Intel runner. CLISP verification uses the distro package rather than Roswell and runs only
when explicitly selected; that build fails the threading dependency check.
See [Support](support.md) for verified results and coverage gaps.

[`.build.yml`](../.build.yml) also tests SBCL/Linux on sourcehut pushes.
Run `tests/test.sh sbcl` locally before pushing.

## Distribution releases

Version tags publish to [takeiteasy's Quicklisp dist](https://github.com/takeiteasy/ql-dist).
The tag matches the ASDF version, for example `v0.1.0`.
[The notifier workflow](../.github/workflows/ql-dist.yml) uses the repository
secret `QL_DIST_TOKEN` to request a distribution build.
