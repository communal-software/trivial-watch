(in-package #:trivial-watch)

#+(or darwin freebsd netbsd openbsd)
(progn
  (defconstant +watch-open-flags+ #+darwin #x8000 #-darwin 0)
  (cffi:defcfun ("open" %open) :int (path :string) (flags :int))
  (cffi:defcfun ("close" %close) :int (descriptor :int))
  (cffi:defcfun (#+(or darwin freebsd) "__error"
                #+(or netbsd openbsd) "__errno" %kqueue-errno-location) :pointer)

  (defun open-kqueue-source (paths state &key interval recursive)
    (declare (ignore interval recursive))
    (let ((queue (trivial-watch.kqueue:open-queue))
          (open-target (symbol-function '%open))
          (descriptors (make-path-table))
          (identities (make-hash-table)))
      (unless queue (return-from open-kqueue-source nil))
      (labels ((remove-target (path)
                 (let ((descriptor (gethash path descriptors)))
                   (when descriptor
                     (%close descriptor)
                     (remhash path descriptors)
                     (remhash descriptor identities))))
               (refresh (state)
                 (let* ((wanted (registration-paths paths state))
                        (wanted-set (path-set wanted)))
                   (dolist (path (loop for path being the hash-keys of descriptors collect path))
                     (unless (gethash path wanted-set) (remove-target path)))
                   (dolist (path wanted)
                     (unless (gethash path descriptors)
                       (let ((descriptor (funcall open-target path +watch-open-flags+)))
                         (unless (minusp descriptor)
                           (setf (gethash path descriptors) descriptor
                                 (gethash descriptor identities) path)
                           (unless (trivial-watch.kqueue:change queue descriptor trivial-watch.kqueue:+filter-vnode+
                                             (logior trivial-watch.kqueue:+flag-add+ trivial-watch.kqueue:+flag-clear+)
                                             trivial-watch.kqueue:+note-vnode+)
                             (error "Cannot register kqueue target: ~a" path)))
                         (when (minusp descriptor)
                           (let ((errno (cffi:mem-ref (%kqueue-errno-location) :int)))
                             (unless (member errno '(2 20))
                               (error "Cannot open kqueue target: ~a (errno ~d)" path errno)))))))))
               (wait ()
                 (let ((events (trivial-watch.kqueue:wait queue 64 nil)))
                   (dolist (event events)
                     (destructuring-bind (descriptor filter flags notes) event
                       (declare (ignore flags))
                       ;; A renamed/deleted vnode cannot follow its replacement.
                       (when (and (= filter trivial-watch.kqueue:+filter-vnode+) (logtest #x61 notes))
                         (let ((path (gethash descriptor identities)))
                           (when path (remove-target path))))))
                   events))
               (cleanup ()
                 (maphash (lambda (path descriptor)
                            (declare (ignore path)) (%close descriptor))
                          descriptors)
                 (trivial-watch.kqueue:close-queue queue)))
        (handler-case
            (progn
              (unless (trivial-watch.kqueue:change queue 0 trivial-watch.kqueue:+filter-user+ trivial-watch.kqueue:+flag-add+ 0)
                (error "Cannot register kqueue shutdown event"))
              (refresh state)
              (make-source :wait #'wait :refresh #'refresh
                           :wake (lambda () (trivial-watch.kqueue:wake queue)) :close #'cleanup))
          (error (condition) (cleanup) (error condition))))))

  (when (trivial-watch.kqueue:supported-p)
    (register-backend :kqueue #'open-kqueue-source)
    (setf *default-backend* :kqueue)))
