(defsystem "trivial-watch"
  :description "Watch files and directories for changes."
  :author "George Watson"
  :license "MIT"
  :version "0.1.1"
  :depends-on ("trivial-watch/core"
               #+abcl "trivial-watch/jvm"
               #-abcl "trivial-watch/native")
  :in-order-to ((test-op (test-op "trivial-watch/tests"))))

(defsystem "trivial-watch/core"
  :description "Filesystem snapshots, workers, and backend extensions."
  :license "MIT"
  :version "0.1.1"
  :depends-on ("uiop" "bordeaux-threads")
  :pathname "watch/"
  :serial t
  :components ((:file "package")
               (:file "files")
               (:file "worker")
               (:file "watch")
               (:file "scan")))

(defsystem "trivial-watch/native"
  :depends-on ("trivial-watch/core" "trivial-watch/kqueue" "cffi")
  :pathname "watch/"
  :serial t
  :components ((:file "kqueue") (:file "inotify") (:file "windows")))

(defsystem "trivial-watch/jvm"
  :depends-on ("trivial-watch/core")
  :pathname "watch/"
  :components ((:file "jvm" :if-feature :abcl)))

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
               (:file "watch")
               (:file "backends")
               (:file "inotify" :if-feature (:and :linux (:not :abcl)))
               (:file "kqueue" :if-feature (:and (:not :abcl)
                                                 (:or :darwin :freebsd :netbsd :openbsd)))
               (:file "jvm" :if-feature :abcl))
  :perform (test-op (o c)
             (unless (symbol-call :fiveam :run! :trivial-watch)
               (error "trivial-watch tests failed"))))
