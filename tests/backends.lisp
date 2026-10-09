(in-package #:trivial-watch/tests)

(in-suite :trivial-watch)

(test explicit-backends-preserve-the-default
  (let ((default (trivial-watch:backend)))
    (unwind-protect
         (progn
           (trivial-watch:register-backend :test-extension #'trivial-watch::open-scan-source :native-p nil)
           (is (eq default (trivial-watch:backend)))
           (is (eq :test-extension (trivial-watch:backend :test-extension)))
           (is-false (trivial-watch:native-p :test-extension))
           (with-directory
             (let* ((file (write-file "custom.txt" "one"))
                    (seen (bt2:make-semaphore))
                    (release (trivial-watch:watch (list file)
                                          (lambda () (bt2:signal-semaphore seen))
                                          :backend :test-extension :interval 0.05)))
               (is-true release)
               (unwind-protect
                    (progn
                      (trivial-watch:register-backend :test-extension
                                              (lambda (&rest args) (declare (ignore args)) nil))
                      (write-file "custom.txt" "two")
                      (is-true (bt2:wait-on-semaphore seen :timeout 5))
                      (is-false (trivial-watch:watch (list file) #'identity :backend :test-extension)))
                 (when release (funcall release))))))
      (remhash :test-extension trivial-watch::*backends*))))

(test unknown-and-reserved-backends-are-errors
  (signals error (trivial-watch:backend :unknown-backend))
  (signals error (trivial-watch:watch nil #'identity :backend :unknown-backend))
  (signals error (trivial-watch:register-backend :default #'identity)))


(test callbacks-follow-the-final-source-refresh
  (with-directory
    (let* ((directory *directory*)
           (file (write-file "final.txt" "one"))
           (notify (bt2:make-semaphore))
           (seen (bt2:make-semaphore))
           (change-during-refresh nil)
           (refreshed nil)
           (matched nil)
           (release
             (trivial-watch::start-watch
              (list file)
              (lambda ()
                (setf matched (equal refreshed (trivial-watch::snapshot (list file))))
                (bt2:signal-semaphore seen))
              nil nil
              (lambda (paths state)
                (declare (ignore paths state))
                (trivial-watch:make-source
                 :wait (lambda () (bt2:wait-on-semaphore notify) t)
                 :refresh (lambda (state)
                            (setf refreshed state)
                            (when change-during-refresh
                              (setf change-during-refresh nil)
                              (let ((*directory* directory))
                                (write-file "final.txt" "three"))))
                 :wake (lambda () (bt2:signal-semaphore notify))
                 :close (lambda ()))))))
      (is-true release)
      (unwind-protect
           (progn
             (write-file "final.txt" "two")
             (setf change-during-refresh t)
             (bt2:signal-semaphore notify)
             (is-true (bt2:wait-on-semaphore seen :timeout 5))
             (is-true matched))
        (when release (funcall release))))))
