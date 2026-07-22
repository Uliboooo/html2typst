#!/usr/bin/env bash

gleam run -- ./html/*.html && for f in "./html/*.typ"; do typst compile "$f"; done && eza "./html/*.pdf"
