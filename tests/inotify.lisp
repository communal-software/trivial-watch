(in-package #:trivial-watch/tests)

(in-suite :trivial-watch)

(test nonblocking-inotify-reads-retain-eagain
  (let ((descriptor (trivial-watch::%inotify-init #x80800))
        (error-location (trivial-watch::%errno-location)))
    (is (not (minusp descriptor)))
    (unwind-protect
         (cffi:with-foreign-object (buffer :uint8 65536)
           (let ((valid t))
             (dotimes (index 1000)
               (unless (and (= -1 (trivial-watch::%read descriptor buffer 65536))
                            (= 11 (trivial-watch::unix-error error-location)))
                 (setf valid nil)))
             (is-true valid)))
      (unless (minusp descriptor) (trivial-watch::%unix-close descriptor)))))
