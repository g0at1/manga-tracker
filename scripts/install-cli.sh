#!/bin/zsh
# Builds the `mangatracker` command-line tool in Release and copies it to
# ~/.local/bin (or the directory given as the first argument).
#
#   scripts/install-cli.sh                 # → ~/.local/bin/mangatracker
#   scripts/install-cli.sh /usr/local/bin
set -euo pipefail

cd "$(dirname "$0")/../cli"

destination="${1:-$HOME/.local/bin}"

echo "Building mangatracker (release)…"
swift build -c release --quiet
built="$(swift build -c release --show-bin-path)/mangatracker"

mkdir -p "$destination"
cp "$built" "$destination/mangatracker"
echo "Installed to $destination/mangatracker"

case ":$PATH:" in
    *":$destination:"*) ;;
    *) echo "Note: $destination isn't on your PATH." ;;
esac
