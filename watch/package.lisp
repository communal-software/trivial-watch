(defpackage #:trivial-watch
  (:use #:cl)
  (:export #:backend #:native-p #:watch
           #:register-backend #:make-source #:registration-paths
           #:event #:event-p #:event-path #:event-kind))
