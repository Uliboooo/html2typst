// config.typ
#let config(doc) = {
  set page(
    margin: 1cm,
    paper: "a4",
    columns: 2,
  )

  set text(
    font: "Harano Aji Gothic",
    size: 8pt,
  )

  set par(
    leading: 0.6em,
    spacing: 0.2em,
  )

  show heading: set block(
    above: 0.8em,
    below: 0.3em,
  )

  doc
}
