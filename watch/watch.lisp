(in-package #:trivial-watch)

(defvar *backends* (make-hash-table))
(defvar *default-backend* :scan)

(defun register-backend (name opener &key (native-p t))
  "Register OPENER for NAME. Existing watches retain their source."
  (check-type name keyword)
  (when (eq name :default) (error "The backend name :DEFAULT is reserved."))
  (check-type opener function)
  (setf (gethash name *backends*) (cons opener (not (null native-p))))
  name)

(defun backend (&optional (name :default))
  "Resolve NAME, or the automatically selected backend."
  (let ((name (if (eq name :default) *default-backend* name)))
    (unless (gethash name *backends*) (error "Unknown backend: ~s" name))
    name))

(defun native-p (&optional (name :default))
  "Whether NAME waits on backend events rather than the library scan timer."
  (cdr (gethash (backend name) *backends*)))

(defun watch (paths callback &key (interval 1.0) events recursive (backend :default))
  "Watch PATHS using BACKEND. Return a release function, or nil on setup failure."
  (check-type interval (real (0) *))
  (let ((opener (car (gethash (backend backend) *backends*))))
    (start-watch paths callback recursive events
                 (lambda (paths state)
                   (funcall opener paths state :interval interval :recursive recursive)))))
