(defsystem "trivial-watch"
  :description "Watch files and directories for changes."
  :author "George Watson"
  :license "MIT"
  :version "0.1.1"
  :depends-on ("cffi" "uiop" "bordeaux-threads" "trivial-watch/kqueue")
  :pathname "watch/"
  :serial t
  :components ((:file "package")
               (:file "files")
               (:file "worker")
               (:file "kqueue")
               (:file "inotify")
               (:file "windows")
               (:file "scan")
               (:file "watch"))
  :in-order-to ((test-op (test-op "trivial-watch/tests"))))

(defsystem "trivial-watch/kqueue"
  :description "The kqueue calls trivial-watch makes."
  :author "George Watson"
  :license "MIT"
  :version "0.1.1"
  :depends-on ("cffi")
  :pathname "kqueue/"
  :serial t
  :components ((:file "package")
               (:file "kqueue")))

(defsystem "trivial-watch/tests"
  :depends-on ("trivial-watch" "fiveam" "bordeaux-threads" "uiop")
  :pathname "tests/"
  :serial t
  :components ((:file "package")
               (:file "watch"))
  :perform (test-op (o c)
             (unless (symbol-call :fiveam :run! :trivial-watch)
               (error "trivial-watch tests failed"))))
