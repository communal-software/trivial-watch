(in-package #:trivial-notify)

(defun %scan-watch (paths callback interval &key recursive events)
  (start-watch
   paths callback recursive events
   (lambda (paths state)
     (declare (ignore paths state))
     (let ((wake (bt2:make-semaphore)))
       (make-source
        :wait (lambda ()
                (bt2:wait-on-semaphore wake :timeout interval)
                t)
        :refresh (lambda (state) (declare (ignore state)))
        :wake (lambda () (bt2:signal-semaphore wake))
        :close (lambda () nil))))))
