# Backends

`watch` selects a native backend when the platform has a binding, and scanning
otherwise. `(backend)` returns its keyword; `(native-p)` is true for native backends.

| Platform | Backend | Keyword |
|---|---|---|
| macOS | kqueue | `:kqueue` |
| Linux | inotify | `:inotify` |
| Windows | ReadDirectoryChangesW | `:read-directory-changes` |
| FreeBSD, NetBSD, OpenBSD, other platforms | Content scan | `:scan` |

Every backend uses the same [watch API](watch.md), path filtering, event batches,
and optional recursion. There is no Lisp implementation allowlist: implementations
load the ordinary CFFI and threading dependencies and attempt the platform backend.
See [Support](support.md) for verification evidence.

## Native watches

Native registrations precede the initial snapshot. Directory membership changes
reconcile registrations before callbacks. Linux queue overflow and Windows lost
notifications trigger snapshot reconciliation.[^native]

Native setup failure returns nil rather than silently selecting scanning.

## Scanning

Scanning compares file contents and directory entries on a timer. It detects
content changes even when timestamps have one-second resolution. Release interrupts
the timer wait.

## Limitations

- BSD kqueue layouts require separate bindings and platform tests:
  [BSD backend ticket](https://todo.sr.ht/~takeiteasy/trivial-watch/3).
- ABCL's dedicated JVM backend is tracked in
  [the WatchService ticket](https://todo.sr.ht/~takeiteasy/trivial-watch/8).
- Content snapshots have [event precision limits](watch.md#limitations).

[^native]: kqueue tracks vnode replacement and reopens affected descriptors.
    Linux uses nonblocking inotify reads, `poll`, and a shutdown pipe. Windows uses
    overlapped directory reads with an I/O completion port; shutdown cancels and
    drains pending operations before freeing foreign buffers.
