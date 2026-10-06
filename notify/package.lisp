(defpackage #:trivial-notify
  (:use #:cl)
  (:local-nicknames (#:kq #:trivial-notify.kqueue))
  (:export #:backend #:native-p #:watch))
