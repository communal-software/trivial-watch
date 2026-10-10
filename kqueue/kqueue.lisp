(in-package #:trivial-watch.kqueue)

(defun supported-p ()
  ;; TODO: NetBSD before 11 needs a separate __kevent50 layout (https://github.com/communal-software/trivial-watch/issues/2).
  #+netbsd (not (null (ignore-errors (cffi:foreign-symbol-pointer "__kevent100"))))
  #+(or darwin freebsd openbsd) t
  #-(or darwin freebsd netbsd openbsd) nil)

#+(or darwin freebsd netbsd openbsd)
(progn
  (defconstant +filter-vnode+ #+netbsd 3 #-netbsd -4)
  (defconstant +filter-user+ #+netbsd 8 #+freebsd -11 #-(or netbsd freebsd) -10)

  (defconstant +flag-add+ #x0001)
  (defconstant +flag-enable+ #x0004)
  (defconstant +flag-clear+ #x0020)

  (defconstant +note-trigger+ #x01000000)
  (defconstant +note-vnode+ #x0000007f
    "DELETE, WRITE, EXTEND, ATTRIB, LINK, RENAME and REVOKE together.")

  (cffi:defcstruct kevent
    (ident :uintptr)
    (filter #+netbsd :uint32 #-netbsd :int16)
    (flags #+netbsd :uint32 #-netbsd :uint16)
    (fflags :uint32)
    (data #+darwin :intptr #-darwin :int64)
    (udata :pointer)
    #+(or freebsd netbsd) (extensions :uint64 :count 4))

  (cffi:defcstruct timespec
    (seconds :long)
    (nanoseconds :long))

  (cffi:defcfun ("kqueue" %kqueue) :int)

  (cffi:defcfun (#+netbsd "__kevent100" #-netbsd "kevent" %kevent) :int
    (queue :int) (changes :pointer) (change-count #+netbsd :size #-netbsd :int)
    (events :pointer) (event-count #+netbsd :size #-netbsd :int) (timeout :pointer))

  (cffi:defcfun ("close" %close) :int (descriptor :int))
  (cffi:defcfun (#+(or darwin freebsd) "__error"
                #+(or netbsd openbsd) "__errno" %errno-location) :pointer)

  (defun open-queue ()
    "A new queue, or nil if the kernel would not give one."
    (let ((queue (%kqueue)))
      (unless (minusp queue) queue)))

  (defun close-queue (queue)
    (%close queue))

  (defun set-event (event identity interest action notes)
    (cffi:with-foreign-slots ((ident filter flags fflags data udata)
                              event (:struct kevent))
      (setf ident identity filter interest flags action fflags notes
            data 0 udata (cffi:null-pointer)))
    #+(or freebsd netbsd)
    (let ((extensions (cffi:foreign-slot-pointer event '(:struct kevent) 'extensions)))
      (dotimes (index 4) (setf (cffi:mem-aref extensions :uint64 index) 0)))
    event)

  (defun change (queue ident filter flags fflags)
    "Register interest in IDENT and return whether the queue took it."
    (cffi:with-foreign-object (event '(:struct kevent))
      (set-event event ident filter flags fflags)
      (not (minusp (%kevent queue event 1 (cffi:null-pointer) 0
                            (cffi:null-pointer))))))

  (defun wake (queue)
    "Trigger the user event a waiting queue also watches, so it returns."
    (cffi:with-foreign-object (event '(:struct kevent))
      (set-event event 0 +filter-user+ +flag-enable+ +note-trigger+)
      (%kevent queue event 1 (cffi:null-pointer) 0 (cffi:null-pointer))))

  (defun %set-timeout (timespec seconds)
    (multiple-value-bind (whole fraction) (floor seconds)
      (setf (cffi:foreign-slot-value timespec '(:struct timespec) 'seconds)
            whole
            (cffi:foreign-slot-value timespec '(:struct timespec) 'nanoseconds)
            (round (* fraction 1000000000)))
      timespec))

  (defun wait (queue count timeout)
    "Up to COUNT events, as (ident filter flags fflags) lists. Waits TIMEOUT
seconds, or forever if it is nil. Returns nil on timeout or interruption;
other syscall failures signal an error."
    (declare (notinline %kevent))
    (cffi:with-foreign-objects ((events '(:struct kevent) count)
                                (timespec '(:struct timespec)))
      (let* ((error-location (%errno-location))
             (ready (%kevent queue (cffi:null-pointer) 0 events count
                             (if timeout
                                 (%set-timeout timespec timeout)
                                 (cffi:null-pointer)))))
        (when (minusp ready)
          (let ((errno (cffi:mem-ref error-location :int)))
            (if (= errno 4)
                (return-from wait nil)
                (error "kevent wait failed for queue ~d (errno ~d)" queue errno))))
        (loop for index from 0 below ready
              for event = (cffi:mem-aptr events '(:struct kevent) index)
              collect (list (cffi:foreign-slot-value event '(:struct kevent)
                                                     'ident)
                            (cffi:foreign-slot-value event '(:struct kevent)
                                                     'filter)
                            (cffi:foreign-slot-value event '(:struct kevent)
                                                     'flags)
                            (cffi:foreign-slot-value event '(:struct kevent)
                                                     'fflags)))))))
