(in-package #:trivial-notify)

#+darwin
(progn
  (defconstant +o-evtonly+ #x8000)
  (cffi:defcfun ("open" %open) :int (path :string) (flags :int))
  (cffi:defcfun ("close" %close) :int (descriptor :int))

  (defun open-kqueue-source (paths state)
    (let ((queue (kq:open-queue))
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
                       (let ((descriptor (%open path +o-evtonly+)))
                         (unless (minusp descriptor)
                           (setf (gethash path descriptors) descriptor
                                 (gethash descriptor identities) path)
                           (unless (kq:change queue descriptor kq:+filter-vnode+
                                             (logior kq:+flag-add+ kq:+flag-clear+)
                                             kq:+note-vnode+)
                             (error "Cannot register kqueue target: ~a" path)))
                         (when (and (minusp descriptor) (uiop:probe-file* path))
                           (error "Cannot open kqueue target: ~a" path)))))))
               (wait ()
                 (let ((events (kq:wait queue 64 nil)))
                   (dolist (event events)
                     (destructuring-bind (descriptor filter flags notes) event
                       (declare (ignore flags))
                       ;; A renamed/deleted vnode cannot follow its replacement.
                       (when (and (= filter kq:+filter-vnode+) (logtest #x61 notes))
                         (let ((path (gethash descriptor identities)))
                           (when path (remove-target path))))))
                   events))
               (cleanup ()
                 (maphash (lambda (path descriptor)
                            (declare (ignore path)) (%close descriptor))
                          descriptors)
                 (kq:close-queue queue)))
        (handler-case
            (progn
              (unless (kq:change queue 0 kq:+filter-user+ kq:+flag-add+ 0)
                (error "Cannot register kqueue shutdown event"))
              (refresh state)
              (make-source :wait #'wait :refresh #'refresh
                           :wake (lambda () (kq:wake queue)) :close #'cleanup))
          (error (condition) (cleanup) (error condition))))))

  (defun %kqueue-watch (paths callback &key recursive events)
    (start-watch paths callback recursive events #'open-kqueue-source)))
