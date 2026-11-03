#!/bin/zsh
set -euo pipefail

# Same Goat must run on Intel Macs as well as Apple silicon. Fails unless the built macOS app
# binary contains both architectures. Usage: verify-macos-universal.sh path/to/SameGoat.app

app="${1:?usage: verify-macos-universal.sh path/to/SameGoat.app}"
archs="$(lipo -archs "$app/Contents/MacOS/SameGoat")"
print "Architectures in ${app:t}: ${archs}"
for required in x86_64 arm64; do
    if [[ " $archs " != *" $required "* ]]; then
        print -u2 "Universal check failed: ${required} slice missing."
        exit 1
    fi
done
print "Universal check passed."
