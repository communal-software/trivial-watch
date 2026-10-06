(defpackage #:trivial-notify.kqueue
  (:use #:cl)
  (:export #:supported-p
           #:+filter-vnode+ #:+filter-user+
           #:+flag-add+ #:+flag-enable+ #:+flag-clear+
           #:+note-trigger+ #:+note-vnode+
           #:open-queue #:close-queue #:set-event #:change #:wake #:wait))
