import gleeunit
import html2typst

pub fn main() -> Nil {
  gleeunit.main()
}

// タグを実装したら、ここに 1 行足す。
// 期待値が思いつかないときは `gleam run` で実際の出力を見てから書くと早い。

// --- ブロック要素 ----------------------------------------------------------

pub fn paragraph_test() {
  assert html2typst.h2t("<p>hello</p>") == "hello"
}

pub fn paragraphs_are_separated_by_a_blank_line_test() {
  assert html2typst.h2t("<p>one</p><p>two</p>") == "one\n\ntwo"
}

pub fn headings_test() {
  assert html2typst.h2t("<h1>a</h1><h2>b</h2>") == "= a\n\n== b"
}

pub fn unordered_list_test() {
  assert html2typst.h2t("<ul><li>a</li><li>b</li></ul>") == "- a\n- b"
}

// --- インライン要素 --------------------------------------------------------

pub fn strong_test() {
  assert html2typst.h2t("<p>a <strong>b</strong> c</p>") == "a *b* c"
}

pub fn link_test() {
  assert html2typst.h2t("<a href=\"https://a.example\">x</a>")
    == "#link(\"https://a.example\")[x]"
}

pub fn link_without_href_falls_back_to_plain_text_test() {
  assert html2typst.h2t("<a>x</a>") == "x"
}

pub fn line_break_test() {
  assert html2typst.h2t("<p>a<br>b</p>") == "a\\\nb"
}

// --- 壊れやすいところ ------------------------------------------------------

pub fn unknown_tags_keep_their_content_test() {
  assert html2typst.h2t("<div><section><p>kept</p></section></div>") == "kept"
}

pub fn typst_special_characters_are_escaped_test() {
  assert html2typst.h2t("<p>a #b $c *d</p>") == "a \\#b \\$c \\*d"
}

pub fn entities_are_decoded_test() {
  assert html2typst.h2t("<p>a &amp; b &lt;c&gt;</p>") == "a & b \\<c\\>"
}

pub fn html_whitespace_is_collapsed_test() {
  assert html2typst.h2t("<p>a\n   b</p>") == "a b"
}

pub fn void_elements_do_not_swallow_their_siblings_test() {
  assert html2typst.h2t("<p>a<br>b</p><p>c</p>") == "a\\\nb\n\nc"
}

pub fn unclosed_tags_do_not_crash_test() {
  assert html2typst.h2t("<p>a<p>b") == "a\n\nb"
}

pub fn stray_end_tag_does_not_crash_test() {
  assert html2typst.h2t("a</span>b") == "ab"
}

pub fn empty_input_test() {
  assert html2typst.h2t("") == ""
}
