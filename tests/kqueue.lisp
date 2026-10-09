(in-package #:trivial-watch/tests)

(in-suite :trivial-watch)

(test kqueue-wait-reports-an-invalid-queue
  (let ((failure (nth-value 1 (ignore-errors (trivial-watch.kqueue:wait -1 1 0)))))
    (is (typep failure 'error))
    (is-true (search "kevent" (princ-to-string failure)))
    (is-true (search "queue -1" (princ-to-string failure)))
    (is-true (search "errno 9" (princ-to-string failure)))))

(test kqueue-wait-ignores-stale-errno-on-timeout
  (let ((queue (trivial-watch.kqueue:open-queue)))
    (is-true queue)
    (unwind-protect
         (progn
           (setf (cffi:mem-ref (trivial-watch.kqueue::%errno-location) :int) 9)
           (is-false (trivial-watch.kqueue:wait queue 1 0)))
      (trivial-watch.kqueue:close-queue queue))))

(test kqueue-interrupted-wait-returns-without-retrying
  (let ((queue (trivial-watch.kqueue:open-queue))
        (kevent (symbol-function 'trivial-watch.kqueue::%kevent))
        (attempts 0))
    (is-true queue)
    (unwind-protect
         (progn
           (is-true (trivial-watch.kqueue:change queue 0 trivial-watch.kqueue:+filter-user+
                                                trivial-watch.kqueue:+flag-add+ 0))
           (trivial-watch.kqueue:wake queue)
           (setf (symbol-function 'trivial-watch.kqueue::%kevent)
                 (lambda (&rest arguments)
                   (if (= 1 (incf attempts))
                       (progn
                         (setf (cffi:mem-ref (trivial-watch.kqueue::%errno-location) :int) 4)
                         -1)
                       (apply kevent arguments))))
           (is-false (trivial-watch.kqueue:wait queue 1 nil))
           (is (= 1 attempts))
           (let ((events (trivial-watch.kqueue:wait queue 1 0)))
             (is (= 2 attempts))
             (is (= trivial-watch.kqueue:+filter-user+ (second (first events))))))
      (setf (symbol-function 'trivial-watch.kqueue::%kevent) kevent)
      (trivial-watch.kqueue:close-queue queue))))

(test kqueue-wait-failure-stops-and-closes-the-worker
  (with-directory
    (let ((entered (bt2:make-semaphore))
          (proceed (bt2:make-semaphore))
          (closed (bt2:make-semaphore))
          (waits 0)
          (closes 0)
          (callbacks 0)
          (release nil))
      (unwind-protect
           (progn
             (setf release
                   (trivial-watch::start-watch
                    (list *directory*) (lambda () (incf callbacks)) nil nil
                    (lambda (paths state)
                      (let* ((source (trivial-watch::open-kqueue-source paths state))
                             (close (trivial-watch::source-close source)))
                        (setf (trivial-watch::source-wait source)
                              (lambda ()
                                (when (= 1 (incf waits))
                                  (bt2:signal-semaphore entered)
                                  (unless (bt2:wait-on-semaphore proceed :timeout 5)
                                    (error "Timed out waiting to inject kevent failure")))
                                (trivial-watch.kqueue:wait -1 1 0))
                              (trivial-watch::source-close source)
                              (lambda ()
                                (funcall close)
                                (incf closes)
                                (bt2:signal-semaphore closed)))
                        source))))
             (is-true release)
             (is-true (bt2:wait-on-semaphore entered :timeout 5))
             (bt2:signal-semaphore proceed)
             (is-true (bt2:wait-on-semaphore closed :timeout 5))
             (let ((failure (nth-value 1 (ignore-errors (funcall release)))))
               (is (typep failure 'error))
               (is-true (search "kevent" (princ-to-string failure)))
               (is-true (search "errno 9" (princ-to-string failure))))
             (signals error (funcall release))
             (is (= 1 waits))
             (is (= 1 closes))
             (is (zerop callbacks)))
        (bt2:signal-semaphore proceed)
        (when release (ignore-errors (funcall release)))))))

(test kqueue-bindings-match-system-headers
  (let ((file (uiop:getenv "KQUEUE_ABI_FILE")))
    (if (not file)
        (skip "Set KQUEUE_ABI_FILE to the output of tests/kqueue-abi.c")
        (let ((abi (with-open-file (stream file) (let ((*read-eval* nil)) (read stream)))))
          (flet ((check (name value) (is (= value (cdr (assoc name abi))))))
            (check :kevent-size (cffi:foreign-type-size '(:struct trivial-watch.kqueue::kevent)))
            (dolist (slot '(trivial-watch.kqueue::ident trivial-watch.kqueue::filter
                           trivial-watch.kqueue::flags trivial-watch.kqueue::fflags
                           trivial-watch.kqueue::data trivial-watch.kqueue::udata))
              (check (intern (format nil "KEVENT-~a" slot) :keyword)
                     (cffi:foreign-slot-offset '(:struct trivial-watch.kqueue::kevent) slot)))
            #+(or freebsd netbsd)
            (check :kevent-ext (cffi:foreign-slot-offset '(:struct trivial-watch.kqueue::kevent)
                                                        'trivial-watch.kqueue::extensions))
            (check :timespec-size (cffi:foreign-type-size '(:struct trivial-watch.kqueue::timespec)))
            (check :timespec-tv_sec (cffi:foreign-slot-offset '(:struct trivial-watch.kqueue::timespec)
                                                            'trivial-watch.kqueue::seconds))
            (check :timespec-tv_nsec (cffi:foreign-slot-offset '(:struct trivial-watch.kqueue::timespec)
                                                             'trivial-watch.kqueue::nanoseconds))
            (check :evfilt_vnode trivial-watch.kqueue:+filter-vnode+)
            (check :evfilt_user trivial-watch.kqueue:+filter-user+)
            (check :ev_add trivial-watch.kqueue:+flag-add+)
            (check :ev_enable trivial-watch.kqueue:+flag-enable+)
            (check :ev_clear trivial-watch.kqueue:+flag-clear+)
            (check :note_trigger trivial-watch.kqueue:+note-trigger+)
            (check :note-vnode trivial-watch.kqueue:+note-vnode+))))))

(test kqueue-user-event-wakes-a-blocked-wait
  (let* ((queue (trivial-watch.kqueue:open-queue))
         (ready (bt2:make-semaphore))
         (result nil)
         (thread nil))
    (is-true queue)
    (unwind-protect
         (progn
           (is-true (trivial-watch.kqueue:change queue 0 trivial-watch.kqueue:+filter-user+
                                                trivial-watch.kqueue:+flag-add+ 0))
           (setf thread (bt2:make-thread
                         (lambda ()
                           (setf result (trivial-watch.kqueue:wait queue 1 5))
                           (bt2:signal-semaphore ready))))
           (trivial-watch.kqueue:wake queue)
           (is-true (bt2:wait-on-semaphore ready :timeout 6))
           (is (= trivial-watch.kqueue:+filter-user+ (second (first result)))))
      (when thread (bt2:join-thread thread))
      (trivial-watch.kqueue:close-queue queue))))

(test kqueue-registration-uses-the-open-error
  (with-directory
    (let* ((file (write-file "recreated.txt" "one"))
           (paths (list file))
           (state (trivial-watch::snapshot paths))
           (opener (symbol-function 'trivial-watch::%open)))
      (dolist (errno '(2 20 13))
        (let ((attempts 0) (source nil))
          (unwind-protect
               (progn
                 (setf (symbol-function 'trivial-watch::%open)
                       (lambda (path flags)
                         (if (and (trivial-watch::path= path (namestring file))
                                  (= 1 (incf attempts)))
                             (let ((location (trivial-watch::%kqueue-errno-location)))
                               (setf (cffi:mem-ref location :int) errno)
                               -1)
                             (funcall opener path flags))))
                 (if (= errno 13)
                     (signals error (trivial-watch::open-kqueue-source paths state))
                     (progn
                       (setf source (trivial-watch::open-kqueue-source paths state))
                       (is-true source)
                       (is (= 1 attempts))
                       (funcall (trivial-watch::source-refresh source) state)
                       (is (= 2 attempts)))))
            (setf (symbol-function 'trivial-watch::%open) opener)
            (when source (funcall (trivial-watch::source-close source)))))))))

(test kqueue-refresh-preserves-pending-notifications
  (with-directory
    (let* ((file (write-file "replace.txt" "one"))
           (paths (list file))
           (source (trivial-watch::open-kqueue-source paths (trivial-watch::snapshot paths))))
      (is-true source)
      (unwind-protect
           (flet ((wait-for-source ()
                    (let* ((finished (bt2:make-semaphore))
                           (result nil)
                           (completed nil)
                           (thread (bt2:make-thread
                                    (lambda ()
                                      (setf result (ignore-errors
                                                     (funcall (trivial-watch::source-wait source))))
                                      (bt2:signal-semaphore finished)))))
                      (unwind-protect
                           (progn
                             (setf completed (bt2:wait-on-semaphore finished :timeout 5))
                             (and completed result))
                        (unless completed (funcall (trivial-watch::source-wake source)))
                        (bt2:join-thread thread)))))
             (uiop:rename-file-overwriting-target (write-file "temporary.txt" "two") file)
             (funcall (trivial-watch::source-refresh source) (trivial-watch::snapshot paths))
             (is-true (wait-for-source))
             (write-file "replace.txt" "three")
             (is-true (wait-for-source)))
        (when source (funcall (trivial-watch::source-close source)))))))
