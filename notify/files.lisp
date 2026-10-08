(in-package #:trivial-notify)

(defstruct (event (:constructor %make-event (path kind)))
  (path nil :read-only t)
  (kind nil :read-only t))

(defun path= (a b)
  #+(or windows win32 mswindows) (string-equal a b)
  #-(or windows win32 mswindows) (string= a b))

(defun make-path-table ()
  (make-hash-table :test #+(or windows win32 mswindows) #'equalp
                       #-(or windows win32 mswindows) #'equal))

(defun path-set (paths)
  (let ((set (make-path-table)))
    (dolist (path paths) (setf (gethash path set) t))
    set))

(defun unique-paths (paths &optional (key #'identity))
  (let ((seen (make-path-table)))
    (loop for path in paths
          for name = (funcall key path)
          unless (gethash name seen)
            collect path and do (setf (gethash name seen) t))))

(defun normalize-paths (paths)
  (unique-paths
   (mapcar (lambda (path)
             (or (uiop:probe-file* path :truename t)
                 (error "Watch path does not exist: ~a" path)))
           paths)
   #'namestring))

(defun targets (paths)
  (unique-paths
   (loop for path in paths
         collect (namestring path)
         collect (namestring (if (uiop:directory-pathname-p path)
                                   (uiop:pathname-parent-directory-pathname path)
                                   (uiop:pathname-directory-pathname path))))))

(defun stamp (file)
  (ignore-errors
    (with-open-file (stream file :element-type '(unsigned-byte 8))
      (let ((buffer (make-array 65536 :element-type '(unsigned-byte 8)))
            (size 0)
            (hash 14695981039346656037))
        (declare (type (unsigned-byte 64) hash))
        (loop for count = (read-sequence buffer stream)
              while (plusp count)
              do (incf size count)
                 ;; FNV-1a: SXHASH does not hash byte-vector contents portably.
                 (dotimes (index count)
                   (setf hash (ldb (byte 64 0)
                                   (* (logxor hash (aref buffer index))
                                      1099511628211)))))
        (cons size hash)))))

(defun real-directory-p (path)
  (let ((actual (ignore-errors (truename path))))
    (and actual (path= (namestring path) (namestring actual)))))

(defun snapshot (paths &optional recursive)
  (let ((entries (make-path-table)))
    (labels ((record (path value)
               (setf (gethash (namestring path) entries) value))
             (visit (path)
               (cond
                 ((uiop:directory-exists-p path)
                  (record path :directory)
                  (dolist (file
                           #+ecl (remove-if #'uiop:directory-pathname-p
                                            (ignore-errors
                                              (directory (merge-pathnames uiop:*wild-file-for-directory* path)
                                                         :resolve-symlinks nil)))
                           #-ecl (uiop:directory-files path))
                    (record file (stamp file)))
                  ;; ECL's UIOP enumeration resolves directory symlinks.
                  (dolist (directory
                           #+ecl (ignore-errors
                                   (directory (merge-pathnames uiop:*wild-directory* path)
                                              :resolve-symlinks nil))
                           #-ecl (uiop:subdirectories path))
                    (when (real-directory-p directory)
                      (if recursive
                          (visit directory)
                          (record directory :directory)))))
                 ((uiop:probe-file* path) (record path (stamp path))))))
      (dolist (path paths) (visit path)))
    (sort (loop for path being the hash-keys of entries using (hash-value value)
                collect (cons path value))
          #'string< :key #'car)))

(defun snapshot-events (before after)
  (let ((old (make-path-table))
        (new (make-path-table))
        (events nil))
    (dolist (entry before) (setf (gethash (car entry) old) (cdr entry)))
    (dolist (entry after) (setf (gethash (car entry) new) (cdr entry)))
    (maphash (lambda (path value)
               (multiple-value-bind (previous present) (gethash path old)
                 (cond ((not present)
                        (push (%make-event (pathname path) :created) events))
                       ((not (equal previous value))
                        (push (%make-event (pathname path) :modified) events)))))
             new)
    (maphash (lambda (path value)
               (declare (ignore value))
               (unless (nth-value 1 (gethash path new))
                 (push (%make-event (pathname path) :deleted) events)))
             old)
    (sort events #'string< :key (lambda (event) (namestring (event-path event))))))

(defun registration-paths (paths state &optional directories-only)
  (unique-paths
   (append (loop for target in (targets paths)
                 when (uiop:probe-file* target)
                   when (or (not directories-only)
                            (uiop:directory-exists-p target))
                     collect target)
           (loop for (path . value) in state
                 when (or (not directories-only) (eq value :directory))
                   collect path))))
