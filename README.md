# trivial-watch

> **Work in progress.** This project is under development; expect missing features and breaking changes.

Watch files and directories for changes, with the best backend the platform
has: kqueue on macOS and BSDs, inotify on Linux, ReadDirectoryChangesW on Windows,
WatchService on ABCL, and a content scan elsewhere.

```lisp
(asdf:load-system "trivial-watch")

(trivial-watch:watch (list #p"src/") (lambda () (print :changed)))
```

## Support

| Implementation | Linux | macOS | Windows |
|---|---|---|---|
| SBCL | CI | CI, ARM64 | CI |
| ECL | CI | CI, ARM64 | Untested |
| CCL | CI | CI, Intel | Untested |
| ABCL | CI | CI, ARM64 | CI |
| CLISP | CI, threaded source build | Untested | Untested |
| LispWorks, Allegro | Untested | Untested | Untested |

Untested implementations are free to attempt loading. See [support details](docs/support.md)
for verification evidence and [coverage gaps](docs/support.md#limitations).

## Docs

- [Watching files](docs/watch.md)
- [Backends](docs/backends.md)
- [Backend extensions](docs/backend-extensions.md)
- [CI](docs/ci.md)
- [Support and testing](docs/support.md)

## License

```text
The MIT License (MIT)

Copyright (c) 2026 George Watson

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software,
and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
