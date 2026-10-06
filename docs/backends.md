# Backends

`watch` picks the best backend the platform has.

| Platform | Backend |
|---|---|
| macOS | kqueue |
| Linux | scan |
| FreeBSD, NetBSD, OpenBSD | scan |
| Windows | scan |

`(trivial-notify:backend)` names the one in use.

## Fallbacks

The scan backend reads each watched file on a timer and compares its
contents, so a change within the same second as the last scan is still seen.
It costs a read of every watched file per interval.

## Unbound backends

inotify and ReadDirectoryChangesW are not bound yet, nor are the BSD kqueue
layouts: `struct kevent` differs on each BSD, so each needs its own binding,
tested on the platform.
