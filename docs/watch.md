# Watching files

`watch` reports changes to requested files and directories on a worker thread.
It returns a release function, or nil when setup fails.

```lisp
(let ((release (trivial-watch:watch (list #p"src/main.lisp")
                                    (lambda () (print :changed)))))
  (when release
    ;; Keep RELEASE until the watch is no longer needed.
    (funcall release)))
```

## Options

| Option | Default | Behavior |
|---|---|---|
| `:events` | nil | Pass a list of events to the callback when true. |
| `:recursive` | nil | Include descendants of requested directories when true. |
| `:interval` | 1.0 | Positive scan interval in seconds; built-in event backends ignore it. |
| `:backend` | `:default` | Automatic platform selection, or an explicitly registered backend such as `:scan`. |

A directory covers its immediate files and directory entries. Recursive watches
include existing and newly created subtrees, excluding directory symlinks.
Requested paths must exist when setup starts. Watches retain parent registrations
to detect deletion, recreation, and editor saves that replace files. Unrelated
siblings do not trigger callbacks.

## Event batches

```lisp
(trivial-watch:watch
 (list #p"src/")
 (lambda (batch)
   (dolist (event batch)
     (format t "~a ~a~%" (trivial-watch:event-kind event)
                         (trivial-watch:event-path event))))
 :events t :recursive t)
```

| Accessor | Value |
|---|---|
| `event-path` | Absolute pathname, rooted at the requested path's truename. |
| `event-kind` | `:created`, `:modified`, or `:deleted`. |
| `event-p` | Whether a value is an event. |

Batches contain one event per changed path, sorted by namestring. Renames appear
as deletion and creation. Native notifications trigger content snapshots; scanning
compares snapshots on its timer. File contents determine modifications.[^snapshots]
Callbacks are sequential within each watch; several writes may form one batch.

## Releasing a watch

Release is idempotent and wakes idle workers. An external caller waits until the
callback and resource cleanup finish. A callback may release its own watch;
cleanup follows when it returns.

Setup failure releases partial registrations and returns nil. Native setup failure
does not switch to scanning. A worker or callback error stops the watch, emits a
warning, and is re-signaled by a later external release.

## Limitations

- A change that appears and disappears between snapshots can be missed; this
  includes a rename away and back. This is not a filesystem audit log.
- Metadata-only changes and replacement with identical contents are not reported.
- Snapshot reads can observe a file during a write, producing intermediate batches.
- Native registrations use OS resources proportional to the covered paths;
  snapshots read covered files after notifications. Narrowing those reads is
  tracked in [the performance ticket](https://todo.sr.ht/~takeiteasy/trivial-watch/11).
- Implementation verification gaps are listed in [Support](support.md#limitations).

[^snapshots]: Snapshots hash files in 64 KiB chunks using FNV-1a and include file
    length. Hash collisions are possible. Scanning hashes every covered file each
    interval; native watches do so after notification, including unrelated parent
    events before filtering.
