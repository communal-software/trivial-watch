(in-package #:trivial-watch/tests)

(in-suite :trivial-watch)

(test snapshot-input-allows-replacement-while-open
  (with-directory
    (let ((file (write-file "replace.txt" "one")))
      (with-open-stream (stream (trivial-watch::open-snapshot-input file))
        (uiop:rename-file-overwriting-target (write-file "temporary.txt" "two") file)
        (is (= (char-code #\o) (read-byte stream))))
      (is-true (trivial-watch::stamp file)))))

(test abcl-loads-without-cffi
  (is-false (find-package :cffi))
  (is (eq :watch-service (trivial-watch:backend))))

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
                 "reset" (lambda () (java:jfield-raw "java.lang.Boolean" (if valid "TRUE" "FALSE")))
                 "isValid" (lambda () (java:jfield-raw "java.lang.Boolean" (if valid "TRUE" "FALSE")))
                 "cancel" (lambda () (setf valid nil) java:+null+)
                 "watchable" (lambda () java:+null+))))
      (is-true (trivial-watch::drain-watch-key key))
      (is-true drained)
      (setf drained nil valid nil)
      (is-false (trivial-watch::drain-watch-key key))
      (is-true drained))))

(test watch-service-closing-unblocks-take
  (with-directory
    (let* ((paths (list *directory*))
           (source (trivial-watch::open-jvm-source paths (trivial-watch::snapshot paths)))
           (finished (bt2:make-semaphore))
           (result t)
           (thread (bt2:make-thread
                    (lambda ()
                      (setf result (handler-case (funcall (trivial-watch::source-wait source))
                                     (error (condition) condition)))
                      (bt2:signal-semaphore finished)))))
      (unwind-protect
           (progn
             (funcall (trivial-watch::source-wake source))
             (is-true (bt2:wait-on-semaphore finished :timeout 5))
             (is-false result))
        (funcall (trivial-watch::source-close source))
        (bt2:join-thread thread)))))
