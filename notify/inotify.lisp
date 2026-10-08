(in-package #:trivial-notify)

#+linux
(progn
  (cffi:defcfun ("__errno_location" %errno-location) :pointer)
  (defun unix-error () (cffi:mem-ref (%errno-location) :int))
  (cffi:defcfun ("inotify_init1" %inotify-init) :int (flags :int))
  (cffi:defcfun ("inotify_add_watch" %inotify-add) :int
    (descriptor :int) (path :string) (mask :uint32))
  (cffi:defcfun ("inotify_rm_watch" %inotify-remove) :int
    (descriptor :int) (watch :int))
  (cffi:defcfun ("pipe2" %pipe) :int (descriptors :pointer) (flags :int))
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

  (defun decode-inotify-events (buffer count ignored overflow)
    (loop with offset = 0
          while (< offset count)
          do (when (< (- count offset) 16) (error "Truncated inotify header"))
             (cffi:with-foreign-slots ((watch mask length)
                                      (cffi:inc-pointer buffer offset) (:struct inotify-event))
               (when (> (+ offset 16 length) count) (error "Truncated inotify event"))
               (cond ((logtest #x4000 mask) (funcall overflow))
                     ((logtest #x8000 mask) (funcall ignored watch)))
               (incf offset (+ 16 length))))
    (plusp count))

  (defun open-inotify-source (paths state)
    (let ((descriptor (%inotify-init #x80800))
          (reader nil) (writer nil)
          (watches (make-path-table))
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
                 (let* ((wanted (registration-paths paths state t))
                        (wanted-set (path-set wanted)))
                   (dolist (path (loop for path being the hash-keys of watches collect path))
                     (unless (gethash path wanted-set) (remove-watch path)))
                   (dolist (path wanted)
                     (unless (gethash path watches)
                       ;; Changes only: reading snapshots must not trigger notifications.
                       (let ((watch (%inotify-add descriptor path #x01000fce)))
                         (cond
                           ((not (minusp watch))
                            (setf (gethash path watches) watch
                                  (gethash watch identities) path))
                           ((uiop:probe-file* path)
                            (error "Cannot register inotify target: ~a" path))))))))
               (read-events ()
                 (let ((changed nil))
                   (cffi:with-foreign-object (buffer :uint8 65536)
                     (loop for count = (%read descriptor buffer 65536)
                           do (cond
                                ((plusp count)
                                 (decode-inotify-events
                                  buffer count
                                  (lambda (watch)
                                    (let ((path (gethash watch identities)))
                                      (when path
                                        (remhash path watches)
                                        (remhash watch identities))))
                                  #'reset)
                                 (setf changed t))
                                ((zerop count) (error "inotify descriptor closed"))
                                ((= (unix-error) 4))
                                ((= (unix-error) 11) (return))
                                (t (error "inotify read failed: ~d" (unix-error))))))
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
                     (when (and (minusp ready) (/= (unix-error) 4))
                       (error "inotify poll failed: ~d" (unix-error)))
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
                (when (minusp (%pipe fds #x80000)) (error "Cannot open shutdown pipe"))
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
