;;;; scan.lisp — the fallback where no native filesystem events exist

(in-package #:trivial-notify)

(defconstant +scan-slice+ 0.05
  "How long a scan sleeps at a time, so a release is not waited out.")

(defun %sleep-while (seconds running)
  (loop repeat (max 1 (round seconds +scan-slice+))
        while (car running)
        do (sleep +scan-slice+)))

(defun %scan-watch (paths callback interval)
  (let ((running (list t))
        (state (snapshot paths)))
    (let ((thread (bt2:make-thread
                   (lambda ()
                     (loop while (car running)
                           do (%sleep-while interval running)
                              (let ((new (snapshot paths)))
                                (unless (equal new state)
                                  (setf state new)
                                  (when (car running)
                                    (funcall callback))))))
                   :name "trivial-notify scan")))
      (lambda ()
        (setf (car running) nil)
        (ignore-errors (bt2:join-thread thread))
        nil))))
