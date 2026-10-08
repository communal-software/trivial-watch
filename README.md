# trivial-notify

> **Work in progress.** This project is under development; expect missing features and breaking changes.

Watch files and directories for changes, with the best backend the platform
has: kqueue on macOS, inotify on Linux, ReadDirectoryChangesW on Windows,
and a content scan elsewhere.

```lisp
(asdf:load-system "trivial-notify")

(trivial-notify:watch (list #p"src/") (lambda () (print :changed)))
```

## Support

| Implementation | Linux | macOS | Windows |
|---|---|---|---|
| SBCL | CI pending | Verified, ARM64 | CI pending |
| ECL | CI pending | Verified, ARM64 | Untested |
| CCL | CI pending | ARM64 verification fails; Intel pending | Untested |
| CLISP | Distro build fails dependency check | Untested | Untested |
| LispWorks, Allegro | Untested | Untested | Untested |

Untested implementations are free to attempt loading. See [support details](docs/support.md)
for verification evidence and [coverage gaps](docs/support.md#limitations).

## Docs

- [Watching files](docs/notify.md)
- [Backends](docs/backends.md)
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
