(defpackage #:trivial-watch
  (:use #:cl)
  (:local-nicknames (#:kq #:trivial-watch.kqueue))
  (:export #:backend #:native-p #:watch
           #:event #:event-p #:event-path #:event-kind))
