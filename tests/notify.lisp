(in-package #:trivial-notify/tests)

(in-suite :trivial-notify)

(defvar *directory* nil)

(defmacro with-directory (&body body)
  "Run BODY with *DIRECTORY* a directory of its own, removed afterwards."
  `(let ((*directory* (truename (ensure-directories-exist
                       (merge-pathnames
                        (format nil "trivial-notify-~36r/" (random (expt 2 48)))
                        (uiop:temporary-directory))))))
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
  (is (member (notify:backend) '(:kqueue :inotify :read-directory-changes :scan)))
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

(defmacro with-event-watch ((paths &key recursive) &body body)
  `(dolist (mode '(:native :scan))
     (let* ((seen (bt2:make-semaphore))
            (lock (bt2:make-lock))
            (batches nil)
            (callback (lambda (batch)
                        (bt2:with-lock-held (lock) (push batch batches))
                        (bt2:signal-semaphore seen)))
            (release (if (eq mode :scan)
                         (notify::%scan-watch ,paths callback 0.05
                                             :events t :recursive ,recursive)
                         (notify:watch ,paths callback :interval 0.05
                                       :events t :recursive ,recursive))))
       (is-true release)
       (unwind-protect
            (flet ((await (path kind)
                     (loop with deadline = (+ (get-internal-real-time)
                                              (* 5 internal-time-units-per-second))
                           do (when (bt2:with-lock-held (lock)
                                      (let ((found (loop for batch in batches
                                                         thereis (find-if
                                                                  (lambda (event)
                                                                    (and (notify::path= (namestring (notify:event-path event)) (namestring path))
                                                                         (eq (notify:event-kind event) kind)))
                                                                  batch))))
                                        (when found
                                          (setf batches (mapcar (lambda (batch) (remove found batch)) batches))
                                          t)))
                                (return t))
                           while (< (get-internal-real-time) deadline)
                           do (bt2:wait-on-semaphore seen :timeout 0.1)))
                   (quiet-p () (not (bt2:wait-on-semaphore seen :timeout 0.3))))
              ,@body)
         (when release (funcall release))))))

(test event-batches-cover-create-modify-and-delete
  (with-directory
    (with-event-watch ((list *directory*))
      (let ((path (write-file "events.txt" "one")))
        (is-true (await path :created))
        (write-file "events.txt" "two")
        (is-true (await path :modified))
        (delete-file path)
        (is-true (await path :deleted))))))

(test parent-events-do-not-report-unrelated-siblings
  (with-directory
    (let ((path (write-file "selected.txt" "one")))
      (with-event-watch ((list path))
        (write-file "sibling.txt" "two")
        (is-true (quiet-p))))))

(test atomic-replacement-keeps-watching-the-new-file
  (with-directory
    (let ((path (write-file "replace.txt" "one")))
      (with-event-watch ((list path))
        (let ((replacement (write-file "temporary.txt" "two")))
          (uiop:rename-file-overwriting-target replacement path))
        (is-true (await path :modified))
        (write-file "replace.txt" "three")
        (is-true (await path :modified))
        (delete-file path)
        (is-true (await path :deleted))
        (write-file "replace.txt" "four")
        (is-true (await path :created))
        (write-file "replace.txt" "five")
        (is-true (await path :modified))))))

(test recursive-watches-cover-new-subtrees
  (with-directory
    (with-event-watch ((list *directory*) :recursive t)
      (let* ((directory (ensure-directories-exist (merge-pathnames "nested/" *directory*)))
             (path (write-file "nested/file.txt" "one")))
        (is-true (await directory :created))
        (is-true (await path :created))
        (write-file "nested/file.txt" "two")
        (is-true (await path :modified))
        (delete-file path)
        (is-true (await path :deleted))
        (uiop:delete-empty-directory directory)
        (is-true (await directory :deleted))))))

(test non-recursive-watches-ignore-nested-file-changes
  (with-directory
    (ensure-directories-exist (merge-pathnames "existing/" *directory*))
    (write-file "existing/file.txt" "one")
    (with-event-watch ((list *directory*))
      (write-file "existing/file.txt" "two")
      (is-true (quiet-p)))))

(test overlapping-paths-produce-one-event-per-path
  (with-directory
    (let* ((path (write-file "overlap.txt" "one"))
           (before (notify::snapshot (list path *directory*))))
      (write-file "overlap.txt" "two")
      (let ((batch (notify::snapshot-events before (notify::snapshot (list path *directory*)))))
        (is (= 1 (length batch)))
        (is (eq :modified (notify:event-kind (first batch))))))))

(test unicode-paths-are-watched
  (with-directory
    (let ((path (write-file "café-λ.txt" "one")))
      (with-event-watch ((list path))
        (write-file "café-λ.txt" (symbol-name mode))
        (is-true (await path :modified))))))

(test release-is-idempotent-and-wakes-an-idle-watch
  (with-directory
    (dolist (mode '(:native :scan))
      (let ((release (if (eq mode :scan)
                         (notify::%scan-watch (list *directory*) (lambda ()) 60)
                         (notify:watch (list *directory*) (lambda ()))))
            (start (get-internal-real-time)))
        (is-true release)
        (funcall release)
        (funcall release)
        (is (< (/ (- (get-internal-real-time) start) internal-time-units-per-second) 2))))))

(test release-can-run-inside-a-callback
  (with-directory
    (dolist (mode '(:native :scan))
      (let* ((done (bt2:make-semaphore))
             (release nil)
             (callback (lambda () (funcall release) (bt2:signal-semaphore done))))
        (setf release (if (eq mode :scan)
                          (notify::%scan-watch (list *directory*) callback 0.05)
                          (notify:watch (list *directory*) callback)))
        (is-true release)
        (unwind-protect
             (progn
               (write-file (format nil "self-release-~a.txt" mode) "one")
               (is-true (bt2:wait-on-semaphore done :timeout 5)))
          (when release (funcall release)))))))

(test failed-setup-returns-nil
  (with-directory
    (is-false (notify:watch (list (merge-pathnames "missing.txt" *directory*)) (lambda ())))
    (is-false (notify:watch nil (lambda ())))
    (is-false (notify:watch (list *directory* (merge-pathnames "missing.txt" *directory*))
                            (lambda ())))))

(test snapshot-renames-are-delete-and-create
  (let ((batch (notify::snapshot-events '(("/old" . (1 . 2))) '(("/new" . (1 . 2))))))
    (is (equal '(:created :deleted) (mapcar #'notify:event-kind batch)))))

#+unix
(test recursive-watches-skip-directory-symlinks
  (with-directory
    (let* ((outside (ensure-directories-exist (merge-pathnames "outside/" *directory*)))
           (root (ensure-directories-exist (merge-pathnames "root/" *directory*)))
           (link (merge-pathnames "link" root)))
      (uiop:run-program (list "ln" "-s" (namestring outside) (namestring link)))
      (unwind-protect
           (with-event-watch ((list root) :recursive t)
             (write-file "outside/ignored.txt" "one")
             (is-true (quiet-p)))
        (delete-file link)))))

(test worker-rolls-back-a-source-when-refresh-fails
  (with-directory
    (let ((closed nil))
      (is-false
       (notify::start-watch
        (list *directory*) (lambda ()) nil nil
        (lambda (paths state)
          (declare (ignore paths state))
          (notify::make-source
           :refresh (lambda (state) (declare (ignore state)) (error "Injected registration failure"))
           :close (lambda () (setf closed t))))))
      (is-true closed))))

(test a-lost-native-batch-recovers-from-the-filesystem
  (with-directory
    (let* ((path (write-file "recover.txt" "one"))
           (added (merge-pathnames "added.txt" *directory*))
           (directory *directory*)
           (seen (bt2:make-semaphore))
           (wake (bt2:make-semaphore))
           (batch nil)
           (first t)
           (refreshes 0)
           (release
             (notify::start-watch
              (list directory) (lambda (events) (setf batch events) (bt2:signal-semaphore seen))
              t t
              (lambda (paths state)
                (declare (ignore paths state))
                (notify::make-source
                 :wait (lambda ()
                         (if first
                             (progn
                               (setf first nil)
                               (with-open-file (out path :direction :output :if-exists :supersede)
                                 (write-string "two" out))
                               (with-open-file (out added :direction :output :if-does-not-exist :create)
                                 (write-string "new" out))
                               :overflow)
                             (bt2:wait-on-semaphore wake)))
                 :refresh (lambda (state) (declare (ignore state)) (incf refreshes))
                 :wake (lambda () (bt2:signal-semaphore wake))
                 :close (lambda () nil))))))
      (is-true release)
      (unwind-protect
           (progn
             (is-true (bt2:wait-on-semaphore seen :timeout 5))
             (is (> refreshes 1))
             (is (equal '(:created :modified) (mapcar #'notify:event-kind batch))))
        (when release (funcall release))))))

(test external-release-waits-for-an-active-callback
  (with-directory
    (let* ((entered (bt2:make-semaphore))
           (resume (bt2:make-semaphore))
           (released (bt2:make-semaphore))
           (release (notify:watch (list *directory*)
                                  (lambda ()
                                    (bt2:signal-semaphore entered)
                                    (bt2:wait-on-semaphore resume))))
           (thread nil))
      (is-true release)
      (unwind-protect
           (progn
             (write-file "callback.txt" "one")
             (is-true (bt2:wait-on-semaphore entered :timeout 5))
             (setf thread (bt2:make-thread
                           (lambda () (funcall release) (bt2:signal-semaphore released))))
             (is-false (bt2:wait-on-semaphore released :timeout 0.1))
             (bt2:signal-semaphore resume)
             (is-true (bt2:wait-on-semaphore released :timeout 5)))
        (bt2:signal-semaphore resume)
        (when release (funcall release))
        (when thread (bt2:join-thread thread))))))

#+linux
(test inotify-overflow-and-ignored-records-are-decoded
  (let ((reset nil) (ignored nil))
    (cffi:with-foreign-object (buffer :uint8 32)
      (loop for offset in '(0 16)
            for mask in '(#x4000 #x8000)
            do (cffi:with-foreign-slots ((notify::watch notify::mask notify::cookie notify::length)
                                         (cffi:inc-pointer buffer offset) (:struct notify::inotify-event))
                 (setf notify::watch 42 notify::mask mask notify::cookie 0 notify::length 0)))
      (is-true (notify::decode-inotify-events buffer 32
                                            (lambda (watch) (setf ignored watch))
                                            (lambda () (setf reset t))))
      (is-true reset)
      (is (= 42 ignored))
      (signals error (notify::decode-inotify-events buffer 1 #'identity (lambda ()))))))
