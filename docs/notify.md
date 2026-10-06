# Watching files

`trivial-notify` calls back when a file or directory changes.

```lisp
(let ((release (trivial-notify:watch (list #p"src/main.lisp")
                                     (lambda () (print :changed)))))
  ;; ...
  (funcall release))
```

| Call | Value |
|---|---|
| `(watch paths callback &key interval)` | A function that ends the watch, or nil if it cannot be opened. |
| `(backend)` | The [backend](backends.md) in use: `:kqueue` or `:scan`. |
| `(native-p)` | Whether the backend waits on events rather than scanning. |

`callback` runs on a thread of its own, once per batch of events. A save
usually arrives as several changes, so expect more calls than saves and
debounce if that matters.

A path can be a file or a directory. Each watched path covers the directory
holding it as well: an editor that saves by writing a new file and renaming
it over the old one only touches the directory.

`interval` is how often the scan backend looks, in seconds. Native backends
ignore it.
