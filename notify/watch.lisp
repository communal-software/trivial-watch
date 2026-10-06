;;;; watch.lisp — the notify half's only entry points

(in-package #:trivial-notify)

(defun backend ()
  "The backend WATCH uses here: :kqueue, or :scan where the platform has no
filesystem events of its own."
  (cond #+darwin ((kq:supported-p) :kqueue)
        (t :scan)))

(defun native-p ()
  "Whether WATCH waits on filesystem events rather than scanning for them."
  (not (eq (backend) :scan)))

(defun watch (paths callback &key (interval 1.0))
  "Call CALLBACK on a thread of its own whenever one of PATHS changes. A
path can be a file or a directory. INTERVAL is how often the scan backend
looks; native backends ignore it. Returns a function that ends the watch,
or nil if the watch cannot be opened."
  (declare (ignorable interval))
  (ecase (backend)
    #+darwin (:kqueue (%kqueue-watch paths callback))
    (:scan (%scan-watch paths callback interval))))
