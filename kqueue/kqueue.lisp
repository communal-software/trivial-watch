;;;; kqueue.lisp — the kqueue calls trivial-notify makes
;;;;
;;;; Darwin only. Every BSD lays struct kevent out differently, so each
;;;; needs its own binding, tested on the platform.

(in-package #:trivial-notify.kqueue)

(defun supported-p ()
  #+darwin t
  #-darwin nil)

#+darwin
(progn
  (defconstant +filter-vnode+ -4)
  (defconstant +filter-user+ -10)

  (defconstant +flag-add+ #x0001)
  (defconstant +flag-enable+ #x0004)
  (defconstant +flag-clear+ #x0020)

  (defconstant +note-trigger+ #x01000000)
  (defconstant +note-vnode+ #x0000006f
    "DELETE, WRITE, EXTEND, ATTRIB, LINK, RENAME and REVOKE together.")

  (cffi:defcstruct kevent
    (ident :uintptr)
    (filter :int16)
    (flags :uint16)
    (fflags :uint32)
    (data :intptr)
    (udata :pointer))

  (cffi:defcstruct timespec
    (seconds :long)
    (nanoseconds :long))

  (cffi:defcfun ("kqueue" %kqueue) :int)

  (cffi:defcfun ("kevent" %kevent) :int
    (queue :int) (changes :pointer) (change-count :int)
    (events :pointer) (event-count :int) (timeout :pointer))

  (cffi:defcfun ("close" %close) :int (descriptor :int))

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
seconds, or forever if it is nil."
    (cffi:with-foreign-objects ((events '(:struct kevent) count)
                                (timespec '(:struct timespec)))
      (let ((ready (%kevent queue (cffi:null-pointer) 0 events count
                            (if timeout
                                (%set-timeout timespec timeout)
                                (cffi:null-pointer)))))
        (loop for index from 0 below (max ready 0)
              for event = (cffi:mem-aptr events '(:struct kevent) index)
              collect (list (cffi:foreign-slot-value event '(:struct kevent)
                                                     'ident)
                            (cffi:foreign-slot-value event '(:struct kevent)
                                                     'filter)
                            (cffi:foreign-slot-value event '(:struct kevent)
                                                     'flags)
                            (cffi:foreign-slot-value event '(:struct kevent)
                                                     'fflags)))))))
