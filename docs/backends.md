# Backends

`watch` selects the platform backend automatically. Use `:backend` to select a
registered backend explicitly. `(backend)` returns the default keyword;
`(native-p)` is true for event-driven backends, including JVM WatchService.[^jvm]

| Platform | Backend | Keyword |
|---|---|---|
| macOS, FreeBSD, NetBSD, OpenBSD | kqueue | `:kqueue` |
| Linux | inotify | `:inotify` |
| Windows | ReadDirectoryChangesW | `:read-directory-changes` |
| ABCL on Linux, macOS, Windows | JVM WatchService | `:watch-service` |
| Other platforms, core-only loading | Content scan | `:scan` |

Every backend uses the same [watch API](watch.md), path filtering, event batches,
and optional recursion. There is no Lisp implementation allowlist. Native bindings use CFFI; ABCL uses
Java interop. Both share Bordeaux Threads workers.
See [Support](support.md) for verification evidence.

## Native watches

Native registrations precede the initial snapshot. Directory membership changes
reconcile registrations before callbacks. Linux queue overflow and Windows lost
notifications trigger snapshot reconciliation.[^native]

Native setup failure returns nil rather than silently selecting scanning.

## Extensions

Load `trivial-watch/core` to use scanning and custom sources without CFFI.
See [Backend extensions](backend-extensions.md) for the registration contract
and a runnable example. Registration does not change automatic selection.

## Scanning

Scanning compares file contents and directory entries on a timer. It detects
content changes even when timestamps have one-second resolution. Release interrupts
the timer wait.

## Limitations

- BSD verification covers x86-64 guests. Other architectures remain unverified.
- JVM notification latency and filesystem coverage depend on the Java provider.[^jvm]
- Content snapshots have [event precision limits](watch.md#limitations).

[^native]: kqueue tracks vnode replacement and reopens affected descriptors.
    Linux uses nonblocking inotify reads, `poll`, and a shutdown pipe. Windows uses
    overlapped directory reads with an I/O completion port; shutdown cancels and
    drains pending operations before freeing foreign buffers.

[^jvm]: WatchService may use polling internally. `native-p` distinguishes a
    backend event source from the library's own content scan timer; it does not
    guarantee that the provider uses kernel notifications.
