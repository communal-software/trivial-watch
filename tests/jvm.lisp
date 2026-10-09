(in-package #:trivial-watch/tests)

(in-suite :trivial-watch)

(test abcl-loads-without-cffi
  (is-false (find-package :cffi))
  (is (eq :watch-service (watch:backend))))

(test watch-service-drains-overflow-and-resets-invalid-keys
  (let ((drained nil)
        (valid t))
    (let* ((overflow (java:jinterface-implementation
                      "java.nio.file.WatchEvent"
                      "kind" (lambda () (java:jfield "java.nio.file.StandardWatchEventKinds" "OVERFLOW"))
                      "count" (lambda () 1)
                      "context" (lambda () java:+null+)))
           (key (java:jinterface-implementation
                 "java.nio.file.WatchKey"
                 "pollEvents" (lambda ()
                                (setf drained t)
                                (java:jstatic "singletonList" "java.util.Collections" overflow))
                 "reset" (lambda () (java:jfield "java.lang.Boolean" (if valid "TRUE" "FALSE")))
                 "isValid" (lambda () (java:jfield "java.lang.Boolean" (if valid "TRUE" "FALSE")))
                 "cancel" (lambda () (setf valid nil) java:+null+)
                 "watchable" (lambda () java:+null+))))
      (is-true (watch::drain-watch-key key))
      (is-true drained)
      (setf drained nil valid nil)
      (is-false (watch::drain-watch-key key))
      (is-true drained))))

(test watch-service-closing-unblocks-take
  (with-directory
    (let* ((paths (list *directory*))
           (source (watch::open-jvm-source paths (watch::snapshot paths)))
           (finished (bt2:make-semaphore))
           (result t)
           (thread (bt2:make-thread
                    (lambda ()
                      (setf result (handler-case (funcall (watch::source-wait source))
                                     (error (condition) condition)))
                      (bt2:signal-semaphore finished)))))
      (unwind-protect
           (progn
             (funcall (watch::source-wake source))
             (is-true (bt2:wait-on-semaphore finished :timeout 5))
             (is-false result))
        (funcall (watch::source-close source))
        (bt2:join-thread thread)))))
