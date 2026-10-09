(in-package #:cl-user)

(defun custom-watch-example (path callback)
  "Return a release function and a notification function for PATH."
  (let ((notification (bt2:make-semaphore)))
    (trivial-watch:register-backend
     :manual
     (lambda (paths state &key interval recursive)
       (declare (ignore paths state interval recursive))
       (trivial-watch:make-source
        :wait (lambda () (bt2:wait-on-semaphore notification) t)
        :refresh (lambda (state) (declare (ignore state)))
        :wake (lambda () (bt2:signal-semaphore notification))
        :close (lambda () nil))))
    (values (trivial-watch:watch (list path) callback :backend :manual)
            (lambda () (bt2:signal-semaphore notification)))))
