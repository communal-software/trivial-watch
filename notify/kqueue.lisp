;;;; kqueue.lisp — filesystem events through kqueue

(in-package #:trivial-notify)

#+darwin
(progn
  (defconstant +o-evtonly+ #x8000
    "Open for events alone, so a watched file doesn't pin its volume.")

  (cffi:defcfun ("open" %open) :int (path :string) (flags :int))

  (cffi:defcfun ("close" %close) :int (descriptor :int))

  (defun %kqueue-loop (queue callback running)
    (loop while (car running)
          for events = (kq:wait queue 8 1)
          when (and events (car running))
            do (funcall callback)))

  (defun %kqueue-watch (paths callback)
    (let ((queue (kq:open-queue)))
      (when queue
        (let ((descriptors (loop for target in (targets paths)
                                 for descriptor = (%open target +o-evtonly+)
                                 unless (minusp descriptor)
                                   collect descriptor))
              (running (list t)))
          (kq:change queue 0 kq:+filter-user+ kq:+flag-add+ 0)
          (dolist (descriptor descriptors)
            (kq:change queue descriptor kq:+filter-vnode+
                       (logior kq:+flag-add+ kq:+flag-clear+)
                       kq:+note-vnode+))
          (let ((thread (bt2:make-thread
                         (lambda () (%kqueue-loop queue callback running))
                         :name "trivial-notify")))
            (lambda ()
              (setf (car running) nil)
              (kq:wake queue)
              (ignore-errors (bt2:join-thread thread))
              (mapc #'%close descriptors)
              (kq:close-queue queue)
              nil)))))))
