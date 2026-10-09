(in-package #:trivial-watch)

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

(defun existing-path (path)
  (uiop:probe-file* path :truename t))

(defun normalize-paths (paths)
  (unique-paths
   (mapcar (lambda (path)
             (or (existing-path path)
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

(defun open-snapshot-input (file)
  #-(or ccl abcl)
  (open file :direction :input :element-type '(unsigned-byte 8)
             :if-does-not-exist nil)
  #+abcl
  ;; NIO input streams allow Windows to replace the file while it is open.
  (let* ((path (java:jstatic "get" "java.nio.file.Paths" (namestring file)
                            (java:jnew-array "java.lang.String" 0)))
         (input (java:jstatic "newInputStream" "java.nio.file.Files" path
                             (java:jnew-array "java.nio.file.OpenOption" 0))))
    (handler-case
        (java:jobject-lisp-value
         (java:jnew "org.armedbear.lisp.Stream" 'stream input '(unsigned-byte 8)))
      (error (condition)
        (java:jcall "close" input)
        (error condition))))
  #+ccl
  ;; CCL's pathname input stream can create files between its two probes.
  (let ((descriptor (ccl::fd-open (ccl::native-translated-namestring file) 0)))
    (when (minusp descriptor) (return-from open-snapshot-input nil))
    (handler-case
        (ccl::make-fd-stream descriptor :direction :input :interactive nil
                                       :element-type '(unsigned-byte 8))
      (error (condition)
        (ccl::fd-close descriptor)
        (error condition)))))

#+(and clisp unix)
(progn
  (ffi:def-call-out %snapshot-open
    (:name "open") (:library :default) (:language :stdc)
    (:arguments (path ffi:c-string) (flags ffi:int)) (:return-type ffi:int))
  (ffi:def-call-out %snapshot-read
    (:name "read") (:library :default) (:language :stdc)
    (:arguments (descriptor ffi:int) (buffer ffi:c-pointer) (count ffi:ulong))
    (:return-type ffi:long))
  (ffi:def-call-out %snapshot-close
    (:name "close") (:library :default) (:language :stdc)
    (:arguments (descriptor ffi:int)) (:return-type ffi:int)))

(defun stamp-blocks (read-block)
  (let ((size 0) (hash 14695981039346656037))
    (declare (type (unsigned-byte 64) hash))
    (loop
      (multiple-value-bind (buffer count) (funcall read-block)
        (when (zerop count) (return (cons size hash)))
        (incf size count)
        ;; FNV-1a: SXHASH does not hash byte-vector contents portably.
        (dotimes (index count)
          (setf hash (ldb (byte 64 0)
                          (* (logxor hash (aref buffer index)) 1099511628211))))))))

(defun stamp (file)
  (ignore-errors
    #+(and clisp unix)
    ;; Lisp file streams participate in CLISP's duplicate-open checks.
    (let ((descriptor (%snapshot-open (namestring file) 0)))
      (when (minusp descriptor) (return-from stamp nil))
      (unwind-protect
           (ffi:with-foreign-object (buffer '(ffi:c-array ffi:uint8 65536))
             (let ((pointer (ffi:foreign-address buffer)))
               (stamp-blocks
                (lambda ()
                  (let ((count (%snapshot-read descriptor pointer 65536)))
                    (when (minusp count) (error "Snapshot read failed: ~a" file))
                    (values (when (plusp count)
                              (ffi:memory-as pointer
                                             (ffi:parse-c-type `(ffi:c-array ffi:uint8 ,count))))
                            count))))))
        (%snapshot-close descriptor)))
    #-(and clisp unix)
    (with-open-stream (stream (open-snapshot-input file))
      (unless stream (return-from stamp nil))
      (let ((buffer (make-array 65536 :element-type '(unsigned-byte 8))))
        (stamp-blocks (lambda () (values buffer (read-sequence buffer stream))))))))

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
                           #+(or ecl sbcl abcl) (remove-if #'uiop:directory-pathname-p
                                            (ignore-errors
                                              (directory (merge-pathnames uiop:*wild-file-for-directory* path)
                                                         :resolve-symlinks nil)))
                           #-(or ecl sbcl abcl) (uiop:directory-files path))
                    (record file (stamp file)))
                  ;; Preserve symlink names so REAL-DIRECTORY-P can exclude them.
                  (dolist (directory
                           #+(or ecl sbcl) (ignore-errors
                                   (directory (merge-pathnames uiop:*wild-directory* path)
                                              :resolve-symlinks nil))
                           #+abcl (remove-if-not #'uiop:directory-pathname-p
                                                (ignore-errors
                                                  (directory (merge-pathnames uiop:*wild-file-for-directory* path)
                                                             :resolve-symlinks nil)))
                           #+clisp (mapcar #'first
                                           (ignore-errors
                                             (directory (merge-pathnames uiop:*wild-directory* path)
                                                        :full t :circle t :if-does-not-exist :ignore)))
                           #-(or ecl sbcl abcl clisp) (uiop:subdirectories path))
                    (when (real-directory-p directory)
                      (if recursive
                          (visit directory)
                          (record directory :directory)))))
                 ((existing-path path) (record path (stamp path))))))
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
                 when (existing-path target)
                   when (or (not directories-only)
                            (uiop:directory-exists-p target))
                     collect target)
           (loop for (path . value) in state
                 when (or (not directories-only) (eq value :directory))
                   collect path))))
