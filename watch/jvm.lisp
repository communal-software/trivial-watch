(in-package #:trivial-watch)

(defun java-path (path)
  (java:jstatic "get" "java.nio.file.Paths" (namestring (pathname path))
                (java:jnew-array "java.lang.String" 0)))

(defun watch-kinds ()
  (let ((kinds (java:jnew-array "java.nio.file.WatchEvent$Kind" 3)))
    (loop for index from 0
          for name in '("ENTRY_CREATE" "ENTRY_MODIFY" "ENTRY_DELETE")
          do (java:jarray-set kinds (java:jfield "java.nio.file.StandardWatchEventKinds" name) index))
    kinds))

(defun drain-watch-key (key)
  (java:jcall (load-time-value (java:jmethod "java.nio.file.WatchKey" "pollEvents")) key)
  (java:jcall (load-time-value (java:jmethod "java.nio.file.WatchKey" "reset")) key))

(defun open-jvm-source (paths state &key interval recursive)
  (declare (ignore interval recursive))
  (let* ((filesystem (java:jstatic "getDefault" "java.nio.file.FileSystems"))
         (service (java:jcall (load-time-value (java:jmethod "java.nio.file.FileSystem" "newWatchService"))
                             filesystem))
         (registrations (make-path-table))
         (kinds (watch-kinds))
         (lock (bt2:make-lock :name "WatchService shutdown"))
         (stopped nil))
    (labels ((close-service ()
               (bt2:with-lock-held (lock)
                 (unless stopped
                   (setf stopped t)
                   (java:jcall (load-time-value (java:jmethod "java.nio.file.WatchService" "close")) service))))
             (refresh (state)
               (bt2:with-lock-held (lock)
                 (unless stopped
                   (let* ((wanted (registration-paths paths state t))
                          (wanted-set (path-set wanted)))
                     (dolist (path (loop for path being the hash-keys of registrations collect path))
                       (unless (gethash path wanted-set)
                         (java:jcall (load-time-value (java:jmethod "java.nio.file.WatchKey" "cancel"))
                                     (gethash path registrations))
                         (remhash path registrations)))
                     (dolist (path wanted)
                       (unless (gethash path registrations)
                         (handler-case
                             (setf (gethash path registrations)
                                   (java:jcall
                                    (load-time-value
                                     (java:jmethod "java.nio.file.Path" "register"
                                                   "java.nio.file.WatchService" "[Ljava.nio.file.WatchEvent$Kind;"))
                                    (java-path path) service kinds))
                           (error (condition)
                             (when (existing-path path) (error condition))))))))))
             (wait ()
               (handler-case
                   (let ((key (java:jcall
                               (load-time-value (java:jmethod "java.nio.file.WatchService" "take")) service)))
                     ;; Every key, including OVERFLOW, reconciles a complete snapshot.
                     (unless (drain-watch-key key)
                       (dolist (path (loop for path being the hash-keys of registrations collect path))
                         (when (java:jcall "equals" key (gethash path registrations))
                           (remhash path registrations))))
                     t)
                 (java:java-exception (condition)
                   (if (and (bt2:with-lock-held (lock) stopped)
                            (java:jinstance-of-p (java:java-exception-cause condition)
                                                 "java.nio.file.ClosedWatchServiceException"))
                       nil
                       (error condition))))))
      (handler-case
          (progn
            (refresh state)
            (make-source :wait #'wait :refresh #'refresh :wake #'close-service :close #'close-service))
        (error (condition) (close-service) (error condition))))))

(register-backend :watch-service #'open-jvm-source)
(setf *default-backend* :watch-service)
