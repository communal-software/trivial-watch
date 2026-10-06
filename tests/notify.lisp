(in-package #:trivial-notify/tests)

(in-suite :trivial-notify)

(defvar *directory* nil)

(defmacro with-directory (&body body)
  "Run BODY with *DIRECTORY* a directory of its own, removed afterwards."
  `(let ((*directory* (ensure-directories-exist
                       (merge-pathnames
                        (format nil "trivial-notify-~36r/" (random (expt 2 48)))
                        (uiop:temporary-directory)))))
     (unwind-protect (progn ,@body)
       (uiop:delete-directory-tree *directory* :validate t))))

(defun write-file (name contents)
  (let ((path (merge-pathnames name *directory*)))
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create)
      (write-string contents out))
    path))

(defun changes (watch-paths change &key (backend :default) (interval 0.1))
  "Whether CHANGE, run against a watch on WATCH-PATHS, reaches the callback."
  (let* ((seen (bt2:make-semaphore))
         (release (ecase backend
                    (:default (notify:watch watch-paths
                                            (lambda ()
                                              (bt2:signal-semaphore seen))
                                            :interval interval))
                    (:scan (notify::%scan-watch
                            watch-paths
                            (lambda () (bt2:signal-semaphore seen))
                            interval)))))
    (is-true release "the watch opened")
    (unwind-protect (progn (sleep 0.2)
                           (funcall change)
                           (bt2:wait-on-semaphore seen :timeout 10))
      (funcall release))))

(test a-backend-is-named
  (is (member (notify:backend) '(:kqueue :scan)))
  (is (eq (notify:native-p) (not (eq (notify:backend) :scan)))))

(test a-watched-file-reports-its-change
  (with-directory
    (let ((path (write-file "watched.txt" "one")))
      (is-true (changes (list path) (lambda () (write-file "watched.txt" "two")))))))

(test a-file-added-to-a-watched-directory-is-a-change
  (with-directory
    (is-true (changes (list *directory*)
                      (lambda () (write-file "added.txt" "one"))))))

(test a-quiet-watch-reports-nothing
  (with-directory
    (write-file "quiet.txt" "one")
    (is-false (changes (list (merge-pathnames "quiet.txt" *directory*))
                       (lambda () (sleep 0.5))))))

(test the-scan-backend-sees-a-change
  (with-directory
    (let ((path (write-file "scanned.txt" "one")))
      (is-true (changes (list path)
                        (lambda () (write-file "scanned.txt" "two"))
                        :backend :scan)))))

(test the-scan-backend-sees-a-file-added-to-a-directory
  (with-directory
    (is-true (changes (list *directory*)
                      (lambda () (write-file "scan-added.txt" "one"))
                      :backend :scan))))

(test a-released-watch-stops-reporting
  (with-directory
    (let* ((path (write-file "released.txt" "one"))
           (count 0)
           (release (notify:watch (list path)
                                  (lambda () (incf count))
                                  :interval 0.1)))
      (is-true release)
      (funcall release)
      (write-file "released.txt" "two")
      (sleep 0.5)
      (is (zerop count)))))

(test the-targets-of-a-path-include-its-directory
  (let ((targets (notify::targets (list #p"/tmp/trivial-notify/a.lisp"))))
    (is (member "/tmp/trivial-notify/a.lisp" targets :test #'string=))
    (is (member "/tmp/trivial-notify/" targets :test #'string=))))
