(in-package #:trivial-watch/tests)

(in-suite :trivial-watch)

(defvar *directory* nil)

(defmacro with-directory (&body body)
  "Run BODY with *DIRECTORY* a directory of its own, removed afterwards."
  `(let ((*directory* (truename (ensure-directories-exist
                       (merge-pathnames
                        (format nil "trivial-watch-~36r/" (random (expt 2 48)))
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
                    (:default (trivial-watch:watch watch-paths
                                            (lambda ()
                                              (bt2:signal-semaphore seen))
                                            :interval interval))
                    (:scan (trivial-watch::%scan-watch
                            watch-paths
                            (lambda () (bt2:signal-semaphore seen))
                            interval)))))
    (is-true release "the watch opened")
    (unwind-protect (progn (sleep 0.2)
                           (funcall change)
                           (bt2:wait-on-semaphore seen :timeout 10))
      (funcall release))))

(test a-backend-is-named
  (is (member (trivial-watch:backend) '(:kqueue :inotify :read-directory-changes :watch-service :scan)))
  (is (eq (trivial-watch:native-p) (not (eq (trivial-watch:backend) :scan)))))

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
           (release (trivial-watch:watch (list path)
                                  (lambda () (incf count))
                                  :interval 0.1)))
      (is-true release)
      (funcall release)
      (write-file "released.txt" "two")
      (sleep 0.5)
      (is (zerop count)))))

(test the-targets-of-a-path-include-its-directory
  (let ((targets (trivial-watch::targets (list #p"/tmp/trivial-watch/a.lisp"))))
    (is (member "/tmp/trivial-watch/a.lisp" targets :test #'string=))
    (is (member "/tmp/trivial-watch/" targets :test #'string=))))

(defmacro with-event-watch ((paths &key recursive) &body body)
  `(dolist (mode '(:native :scan))
     (let* ((seen (bt2:make-semaphore))
            (lock (bt2:make-lock))
            (batches nil)
            (callback (lambda (batch)
                        (bt2:with-lock-held (lock) (push batch batches))
                        (bt2:signal-semaphore seen)))
            (release (if (eq mode :scan)
                         (trivial-watch::%scan-watch ,paths callback 0.05
                                             :events t :recursive ,recursive)
                         (trivial-watch:watch ,paths callback :interval 0.05
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
                                                                    (and (trivial-watch::path= (namestring (trivial-watch:event-path event)) (namestring path))
                                                                         (eq (trivial-watch:event-kind event) kind)))
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
           (before (trivial-watch::snapshot (list path *directory*))))
      (write-file "overlap.txt" "two")
      (let ((batch (trivial-watch::snapshot-events before (trivial-watch::snapshot (list path *directory*)))))
        (is (= 1 (length batch)))
        (is (eq :modified (trivial-watch:event-kind (first batch))))))))

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
                         (trivial-watch::%scan-watch (list *directory*) (lambda ()) 60)
                         (trivial-watch:watch (list *directory*) (lambda ()))))
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
                          (trivial-watch::%scan-watch (list *directory*) callback 0.05)
                          (trivial-watch:watch (list *directory*) callback)))
        (is-true release)
        (unwind-protect
             (progn
               (write-file (format nil "self-release-~a.txt" mode) "one")
               (is-true (bt2:wait-on-semaphore done :timeout 5)))
          (when release (funcall release)))))))

(test failed-setup-returns-nil
  (with-directory
    (is-false (trivial-watch:watch (list (merge-pathnames "missing.txt" *directory*)) (lambda ())))
    (is-false (trivial-watch:watch nil (lambda ())))
    (is-false (trivial-watch:watch (list *directory* (merge-pathnames "missing.txt" *directory*))
                            (lambda ())))))

(test snapshot-renames-are-delete-and-create
  (let ((batch (trivial-watch::snapshot-events '(("/old" . (1 . 2))) '(("/new" . (1 . 2))))))
    (is (equal '(:created :deleted) (mapcar #'trivial-watch:event-kind batch)))))

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
       (trivial-watch::start-watch
        (list *directory*) (lambda ()) nil nil
        (lambda (paths state)
          (declare (ignore paths state))
          (trivial-watch::make-source
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
             (trivial-watch::start-watch
              (list directory) (lambda (events) (setf batch events) (bt2:signal-semaphore seen))
              t t
              (lambda (paths state)
                (declare (ignore paths state))
                (trivial-watch::make-source
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
             (is (equal '(:created :modified) (mapcar #'trivial-watch:event-kind batch))))
        (when release (funcall release))))))

(test external-release-waits-for-an-active-callback
  (with-directory
    (let* ((entered (bt2:make-semaphore))
           (resume (bt2:make-semaphore))
           (released (bt2:make-semaphore))
           (release (trivial-watch:watch (list *directory*)
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

#+(and linux (not abcl))
(test inotify-overflow-and-ignored-records-are-decoded
  (let ((reset nil) (ignored nil))
    (cffi:with-foreign-object (buffer :uint8 32)
      (loop for offset in '(0 16)
            for mask in '(#x4000 #x8000)
            do (cffi:with-foreign-slots ((trivial-watch::watch trivial-watch::mask trivial-watch::cookie trivial-watch::length)
                                         (cffi:inc-pointer buffer offset) (:struct trivial-watch::inotify-event))
                 (setf trivial-watch::watch 42 trivial-watch::mask mask trivial-watch::cookie 0 trivial-watch::length 0)))
      (is-true (trivial-watch::decode-inotify-events buffer 32
                                            (lambda (watch) (setf ignored watch))
                                            (lambda () (setf reset t))))
      (is-true reset)
      (is (= 42 ignored))
      (signals error (trivial-watch::decode-inotify-events buffer 1 #'identity (lambda ()))))))

(test a-requested-directory-can-be-deleted-and-recreated
  (with-directory
    (let ((root (ensure-directories-exist (merge-pathnames "watched/" *directory*))))
      (with-event-watch ((list root) :recursive t)
        (uiop:delete-empty-directory root)
        (is-true (await root :deleted))
        (ensure-directories-exist root)
        (is-true (await root :created))
        (let ((path (write-file "watched/new.txt" (symbol-name mode))))
          (is-true (await path :created))
          (delete-file path)
          (is-true (await path :deleted)))))))

(test snapshot-input-does-not-create-missing-files
  (with-directory
    (let ((missing (merge-pathnames "missing.txt" *directory*)))
      (is-false (loop repeat 100 thereis (trivial-watch::stamp missing)))
      (is-false (probe-file missing))
      (is-false (uiop:directory-files *directory*)))))

(test existing-path-covers-directories-and-files
  (with-directory
    (let ((file (write-file "present.txt" "one")))
      (is (equal *directory* (trivial-watch::existing-path *directory*)))
      (is (equal (truename file) (trivial-watch::existing-path file)))
      (is-false (trivial-watch::existing-path (merge-pathnames "missing/" *directory*))))))

(test snapshot-reads-do-not-interfere-with-replacement
  (with-directory
    (let* ((file (write-file "résumé.txt" "one"))
           (stop (bt2:make-semaphore))
           (reader (bt2:make-thread
                    (lambda ()
                      (loop until (bt2:wait-on-semaphore stop :timeout 0)
                            do (trivial-watch::stamp file))))))
      (unwind-protect
           (dotimes (index 100)
             (write-file "résumé.txt" (format nil "value ~d" index)))
        (bt2:signal-semaphore stop)
        (bt2:join-thread reader))
      (is (= 1 (length (uiop:directory-files *directory*))))
      (is (equal (trivial-watch::stamp file) (trivial-watch::stamp file)))
      (delete-file file)
      (is-false (uiop:directory-files *directory*)))))
