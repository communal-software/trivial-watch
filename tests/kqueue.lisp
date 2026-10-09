(in-package #:trivial-watch/tests)

(in-suite :trivial-watch)

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
