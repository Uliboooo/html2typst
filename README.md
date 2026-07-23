# html2typst

[![Package Version](https://img.shields.io/hexpm/v/html2typst)](https://hex.pm/packages/html2typst)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/html2typst/)

Convert HTML into [Typst](https://typst.app/) markup — usable as a Gleam
library or as a small command-line tool that turns `.html` files into
compilable `.typ` documents.

```gleam
import html2typst

pub fn main() {
  html2typst.h2t("<h2>Title</h2><p>Hello <strong>world</strong></p>")
  // -> "= Title\n\nHello *world*"
}
```

## Usage as a library

```sh
gleam add html2typst
```

The whole public API is one function:

```gleam
import html2typst

pub fn main() {
  let typst = html2typst.h2t("<ul><li>a</li><li>b</li></ul>")
  // "- a\n- b"
}
```

`h2t/1` takes an HTML string and returns a Typst-markup string. It does no
file I/O, so you can feed it any source of HTML and do what you like with the
result.

## Usage as a CLI

Running the project converts one or more `.html` files into `.typ` files
next to them, each prefixed with an `#import` / `#show` of a config file so
the result compiles directly with Typst.

```sh
gleam run -- path/to/page.html          # -> path/to/page.typ
gleam run -- a.html b.html c.html       # convert several at once
```

Each output `.typ` starts with:

```typ
#import "./config/config.typ": config
#show: config

...converted body...
```

so page setup (paper size, margins, fonts, columns, …) lives in one place and
is shared across every converted document. See [`config.typ`](config.typ) for
the example config used in this repo.

### End-to-end example

[`script.sh`](script.sh) shows the intended pipeline — convert, then compile
to PDF with Typst:

```sh
gleam run -- ./html/*.html \
  && for f in ./html/*.typ; do typst compile "$f"; done
```

## Development

```sh
gleam run   # run the CLI
gleam test  # run the tests
```

The tests in [`test/html2typst_test.gleam`](test/html2typst_test.gleam)
double as the spec: each one pins down the Typst output for a small HTML
snippet, including the tricky cases (escaping, entities, unclosed tags, void
elements). When you implement a new tag, add a matching assertion there.

A [Nix flake](flake.nix) is provided with a dev shell (`gleam`, `erlang`):

```sh
nix develop
```

Further documentation can be found at <https://hexdocs.pm/html2typst>.

## Concept

HTML and Typst both describe documents, but with different primitives.
html2typst does a **structural translation**, not a visual one: it maps each
HTML construct onto the closest Typst markup and lets Typst handle the actual
layout and typesetting.

The conversion runs in three stages:

1. **Flatten** — `html_parser` turns the HTML string into a flat list of
   start-tags, end-tags, and text.
2. **Build a tree** — that flat list is folded back into a `Node` tree
   (`Element` / `Text`). This stage is tag-agnostic, so it rarely needs to
   change.
3. **Render** — the tree is walked and each node is emitted as Typst markup.
   This is where the actual HTML→Typst mapping lives (`render_element`).

Two ideas guide the mapping:

- **Never drop content.** Unknown or purely structural tags (`div`, `span`,
  `section`, `body`, …) are *unwrapped* — their children are emitted and the
  tag itself disappears. Text is never silently lost.
- **Stay robust on messy HTML.** Unclosed tags, stray end tags, void elements
  (`<br>`, `<img>`, …), and significant whitespace around tags are all handled
  so real-world HTML doesn't crash the converter or scramble the output.

Text is decoded (entities → characters), whitespace-collapsed (HTML rules),
and escaped so that Typst-significant characters (`#`, `$`, `*`, `_`, `[`,
`]`, …) survive as literal text instead of becoming markup.

### What gets mapped

| HTML | Typst |
|------|-------|
| `<p>` | paragraph (blank-line separated) |
| `<h1>` | `#title[...]` |
| `<h2>`…`<h6>` | `=`, `==`, `===`, … headings |
| `<ul>` / `<ol>` | `-` / `+` list items |
| `<strong>` | `*bold*` |
| `<a href>` | `#link("...")[...]` |
| `<br>` | line break (`\`) |
| unknown tags | unwrapped (content kept, tag removed) |

Adding a new tag means adding one arm to the `case` in `render_element` —
see the inline `TODO`s in [`src/html2typst.gleam`](src/html2typst.gleam) for
the ones that are stubbed out (`em`, `code`, `pre`, `blockquote`, `hr`,
`table`, `img`, …).



