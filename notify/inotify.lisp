(in-package #:trivial-notify)

#+linux
(progn
  (cffi:defcfun ("inotify_init1" %inotify-init) :int (flags :int))
  (cffi:defcfun ("inotify_add_watch" %inotify-add) :int
    (descriptor :int) (path :string) (mask :uint32))
  (cffi:defcfun ("inotify_rm_watch" %inotify-remove) :int
    (descriptor :int) (watch :int))
  (cffi:defcfun ("pipe" %pipe) :int (descriptors :pointer))
  (cffi:defcfun ("read" %read) :intptr
    (descriptor :int) (buffer :pointer) (size :size))
  (cffi:defcfun ("write" %write) :intptr
    (descriptor :int) (buffer :pointer) (size :size))
  (cffi:defcfun ("close" %unix-close) :int (descriptor :int))
  (cffi:defcstruct pollfd (descriptor :int) (events :short) (returned :short))
  (cffi:defcfun ("poll" %poll) :int
    (descriptors :pointer) (count :unsigned-long) (timeout :int))
  (cffi:defcstruct inotify-event
    (watch :int) (mask :uint32) (cookie :uint32) (length :uint32))

  (defun open-inotify-source (paths state)
    (let ((descriptor (%inotify-init #x80800))
          (reader nil) (writer nil)
          (watches (make-hash-table :test #'equal))
          (identities (make-hash-table)))
      (when (minusp descriptor) (return-from open-inotify-source nil))
      (labels ((remove-watch (path)
                 (let ((watch (gethash path watches)))
                   (when watch
                     (%inotify-remove descriptor watch)
                     (remhash watch identities)
                     (remhash path watches))))
               (reset ()
                 (dolist (path (loop for path being the hash-keys of watches collect path))
                   (remove-watch path)))
               (refresh (state)
                 (let ((wanted (registration-paths paths state t)))
                   (dolist (path (loop for path being the hash-keys of watches collect path))
                     (unless (member path wanted :test #'path=) (remove-watch path)))
                   (dolist (path wanted)
                     (unless (gethash path watches)
                       ;; Changes only: reading snapshots must not trigger notifications.
                       (let ((watch (%inotify-add descriptor path #x01000fce)))
                         (when (minusp watch)
                           (error "Cannot register inotify target: ~a" path))
                         (setf (gethash path watches) watch
                               (gethash watch identities) path))))))
               (read-events ()
                 (let ((changed nil))
                   (cffi:with-foreign-object (buffer :uint8 65536)
                     (loop for count = (%read descriptor buffer 65536)
                           while (plusp count)
                           do (loop with offset = 0
                                    while (< offset count)
                                    for event = (cffi:inc-pointer buffer offset)
                                    do (cffi:with-foreign-slots ((watch mask length)
                                                               event (:struct inotify-event))
                                         (when (> (+ offset 16 length) count)
                                           (error "Truncated inotify event"))
                                         (cond
                                           ((logtest #x4000 mask) (reset) (setf changed t))
                                           ((logtest #x8000 mask)
                                            (let ((path (gethash watch identities)))
                                              (when path
                                                (remhash path watches)
                                                (remhash watch identities)))
                                            (setf changed t))
                                           (t (setf changed t)))
                                         (incf offset (+ 16 length))))))
                   changed))
               (wait ()
                 (cffi:with-foreign-object (fds '(:struct pollfd) 2)
                   (loop for fd in (list descriptor reader)
                         for index from 0
                         for entry = (cffi:mem-aptr fds '(:struct pollfd) index)
                         do (setf (cffi:foreign-slot-value entry '(:struct pollfd) 'descriptor) fd
                                  (cffi:foreign-slot-value entry '(:struct pollfd) 'events) 1
                                  (cffi:foreign-slot-value entry '(:struct pollfd) 'returned) 0))
                   (let ((ready (%poll fds 2 -1)))
                     (when (plusp ready)
                       (if (plusp (cffi:foreign-slot-value
                                   (cffi:mem-aptr fds '(:struct pollfd) 1)
                                   '(:struct pollfd) 'returned))
                           nil
                           (read-events))))))
               (cleanup ()
                 (%unix-close descriptor)
                 (when reader (%unix-close reader))
                 (when writer (%unix-close writer))))
        (handler-case
            (progn
              (cffi:with-foreign-object (fds :int 2)
                (when (minusp (%pipe fds)) (error "Cannot open shutdown pipe"))
                (setf reader (cffi:mem-aref fds :int 0)
                      writer (cffi:mem-aref fds :int 1)))
              (refresh state)
              (make-source
               :wait #'wait :refresh #'refresh :close #'cleanup
               :wake (lambda ()
                       (cffi:with-foreign-object (byte :uint8)
                         (setf (cffi:mem-ref byte :uint8) 1)
                         (%write writer byte 1)))))
          (error (condition) (cleanup) (error condition))))))

  (defun %inotify-watch (paths callback &key recursive events)
    (start-watch paths callback recursive events #'open-inotify-source)))
