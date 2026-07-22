#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

gleam run -- ./html/*.html

for f in ./html/*.typ; do
  typst compile "$f"
done

pdfs=(./html/*.pdf)
((${#pdfs[@]})) && eza "${pdfs[@]}"
