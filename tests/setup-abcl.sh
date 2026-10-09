#!/bin/sh
set -eu
destination=${1:?Provide the installation directory}
mkdir -p "$destination"
curl -fsSL --retry 5 https://abcl.org/releases/1.9.2/abcl-bin-1.9.2.tar.gz -o "$destination/abcl.tar.gz"
echo "24970976b3565ddf32a1e0b17c5034a9996df25404ec44f240505b01c68a37fe  $destination/abcl.tar.gz" | sha256sum -c -
tar -xzf "$destination/abcl.tar.gz" -C "$destination"
curl -fsSL --retry 5 https://beta.quicklisp.org/quicklisp.lisp -o "$HOME/quicklisp.lisp"
java -jar "$destination/abcl-bin-1.9.2/abcl.jar" --noinit --batch --load tests/install-quicklisp.lisp
