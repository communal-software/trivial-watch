;;;; files.lisp — the paths a watch covers, and how it sees them change

(in-package #:trivial-notify)

(defun targets (paths)
  "PATHS and the directories holding them: an editor that saves by writing a
new file and renaming it over the old one only touches the directory."
  (remove-duplicates
   (loop for path in paths
         collect (namestring path)
         collect (namestring (make-pathname :name nil :type nil
                                            :defaults path)))
   :test #'string=))

(defun stamp (file)
  "A key for FILE's contents, or nil if it cannot be read. FILE-WRITE-DATE
has one-second resolution, too coarse for an edit made while a scan runs, so
this reads the file."
  (ignore-errors
   (with-open-file (stream file :element-type '(unsigned-byte 8))
     (let* ((buffer (make-array (file-length stream)
                                :element-type '(unsigned-byte 8)))
            (count (read-sequence buffer stream))
            (hash 14695981039346656037))
       (declare (type (unsigned-byte 64) hash))
       ;; FNV-1a: SXHASH says nothing useful about a byte vector.
       (dotimes (index count)
         (setf hash (ldb (byte 64 0)
                         (* (logxor hash (aref buffer index))
                            1099511628211))))
       (cons count hash)))))

(defun snapshot (paths)
  "Each watched file and a key for its contents. A directory contributes the
files in it, so one added or removed there shows as a change."
  (sort (loop for path in paths
              append (if (uiop:directory-exists-p path)
                         (loop for file in (uiop:directory-files path)
                               collect (cons (namestring file) (stamp file)))
                         (list (cons (namestring path) (stamp path)))))
        #'string< :key #'car))
