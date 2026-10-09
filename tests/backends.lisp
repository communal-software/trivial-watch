(in-package #:trivial-watch/tests)

(in-suite :trivial-watch)

(test explicit-backends-preserve-the-default
  (let ((default (watch:backend)))
    (unwind-protect
         (progn
           (watch:register-backend :test-extension #'watch::open-scan-source :native-p nil)
           (is (eq default (watch:backend)))
           (is (eq :test-extension (watch:backend :test-extension)))
           (is-false (watch:native-p :test-extension))
           (with-directory
             (let* ((file (write-file "custom.txt" "one"))
                    (seen (bt2:make-semaphore))
                    (release (watch:watch (list file)
                                          (lambda () (bt2:signal-semaphore seen))
                                          :backend :test-extension :interval 0.05)))
               (is-true release)
               (unwind-protect
                    (progn
                      (watch:register-backend :test-extension
                                              (lambda (&rest args) (declare (ignore args)) nil))
                      (write-file "custom.txt" "two")
                      (is-true (bt2:wait-on-semaphore seen :timeout 5))
                      (is-false (watch:watch (list file) #'identity :backend :test-extension)))
                 (when release (funcall release))))))
      (remhash :test-extension watch::*backends*))))

(test unknown-and-reserved-backends-are-errors
  (signals error (watch:backend :unknown-backend))
  (signals error (watch:watch nil #'identity :backend :unknown-backend))
  (signals error (watch:register-backend :default #'identity)))

