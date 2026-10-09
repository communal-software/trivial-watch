(in-package #:trivial-watch)

(defun open-scan-source (paths state &key interval recursive)
  (declare (ignore paths state recursive))
  (let ((wake (bt2:make-semaphore)))
    (make-source
     :wait (lambda () (bt2:wait-on-semaphore wake :timeout interval) t)
     :refresh (lambda (state) (declare (ignore state)))
     :wake (lambda () (bt2:signal-semaphore wake))
     :close (lambda () nil))))

(register-backend :scan #'open-scan-source :native-p nil)

(defun %scan-watch (paths callback interval &key recursive events)
  (watch paths callback :interval interval :recursive recursive :events events :backend :scan))
