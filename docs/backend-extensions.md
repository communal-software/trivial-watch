# Backend extensions

Load `trivial-watch/core` for a CFFI-free watch API, scanning and custom backends.
`trivial-watch` also loads the built-in native bindings, or WatchService on ABCL.

## Register and select

```lisp
(trivial-watch:register-backend :my-source #'open-my-source :native-p t)
(trivial-watch:watch paths callback :backend :my-source :events t)
```

Registration replaces the opener for future watches. Running watches retain their
source. Custom registration leaves automatic platform selection unchanged.
`:default` is reserved; unknown backend names signal an error.

`(backend :my-source)` checks registration and returns its name.
`(native-p :my-source)` returns its event-source classification. `:native-p`
defaults to true; use nil for timer-driven scanners.

## Opener contract

The opener receives `(paths state &key interval recursive)`. Paths are normalized
absolute pathnames; state is an opaque initial snapshot. It returns a source or nil.
The shared worker owns snapshots, filtering, event batches and callbacks.

Use `(registration-paths paths state)` to obtain existing registration namestrings,
including parents and covered descendants. Pass a true third argument for
registrations covering directories only. Refresh uses the same helper with each
new snapshot.

## Source functions

`make-source` takes four function arguments:

| Keyword | Arguments | Contract |
|---|---|---|
| `:wait` | None | Block until notification or shutdown; return true when reconciliation is needed. |
| `:refresh` | Snapshot state | Reconcile registrations; do not modify state. |
| `:wake` | None | Promptly unblock wait from another thread. |
| `:close` | None | Release all source resources. |

Only the worker invokes wait and refresh. Wake may run concurrently with either.
Refresh can run more than once per notification; its final state precedes callbacks.
Close follows worker termination or setup rollback. Openers clean up their own
partial resources if they fail before returning a source. A failed source returns
nil from `watch`; it does not cause fallback to scanning.

Worker errors stop the watch and are reported by external release. Expected
shutdown exceptions belong inside the source's wait function.

## Example

[custom-backend.lisp](../examples/custom-backend.lisp) supplies a manually signalled
source. After changing the watched file, invoke the returned notification function;
the worker computes the event batch. Keep the release function until finished.

```lisp
(asdf:load-system "trivial-watch/core")
(load "examples/custom-backend.lisp")
(multiple-value-bind (release notify)
    (custom-watch-example #p"example.txt" (lambda () (print :changed)))
  ;; Change example.txt, then signal the source.
  (funcall notify)
  (funcall release))
```

## Limitations

- Extensions still require a working filesystem API and Bordeaux Threads.
- Loading the core supplies scanning; it does not implement bindings for other
  implementations automatically.
- Event precision follows the shared [snapshot limitations](watch.md#limitations).
