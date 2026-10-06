(defsystem "trivial-notify"
  :description "Watch files and directories for changes."
  :author "George Watson"
  :license "MIT"
  :version "0.0.0"
  :depends-on ("cffi" "uiop" "bordeaux-threads" "trivial-notify/kqueue")
  :pathname "notify/"
  :serial t
  :components ((:file "package")
               (:file "files")
               (:file "kqueue")
               (:file "scan")
               (:file "watch"))
  :in-order-to ((test-op (test-op "trivial-notify/tests"))))

(defsystem "trivial-notify/kqueue"
  :description "The kqueue calls trivial-notify makes."
  :author "George Watson"
  :license "MIT"
  :version "0.0.0"
  :depends-on ("cffi")
  :pathname "kqueue/"
  :serial t
  :components ((:file "package")
               (:file "kqueue")))

(defsystem "trivial-notify/tests"
  :depends-on ("trivial-notify" "fiveam" "bordeaux-threads" "uiop")
  :pathname "tests/"
  :serial t
  :components ((:file "package")
               (:file "notify"))
  :perform (test-op (o c)
             (unless (symbol-call :fiveam :run! :trivial-notify)
               (error "trivial-notify tests failed"))))
