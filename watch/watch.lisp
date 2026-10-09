(in-package #:trivial-watch)

(defun backend ()
  "The platform backend selected for WATCH."
  (cond #+darwin ((kq:supported-p) :kqueue)
        #+linux (t :inotify)
        #+(or windows win32 mswindows) (t :read-directory-changes)
        (t :scan)))

(defun native-p ()
  "Whether WATCH waits on native events instead of scanning on a timer."
  (not (eq (backend) :scan)))

(defun watch (paths callback &key (interval 1.0) events recursive)
  "Watch PATHS. EVENTS passes a batch to CALLBACK; RECURSIVE covers subtrees.
Return a release function, or nil if the watch cannot be established."
  (check-type interval (real (0) *))
  (ecase (backend)
    #+darwin (:kqueue (%kqueue-watch paths callback :events events :recursive recursive))
    #+linux (:inotify (%inotify-watch paths callback :events events :recursive recursive))
    #+(or windows win32 mswindows)
    (:read-directory-changes
     (%windows-watch paths callback :events events :recursive recursive))
    (:scan (%scan-watch paths callback interval :events events :recursive recursive))))
