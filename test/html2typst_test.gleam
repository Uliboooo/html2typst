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
  assert html2typst.h2t("<h1>a</h1><h2>b</h2>") == "#title[a]\n\n= b"
}

/// h2 が `=` 1 個。h1 は #title に回しているので 1 段ずれる。
pub fn deeper_headings_test() {
  assert html2typst.h2t("<h3>a</h3><h4>b</h4><h5>c</h5><h6>d</h6>")
    == "== a\n\n=== b\n\n==== c\n\n===== d"
}

pub fn horizontal_rule_test() {
  assert html2typst.h2t("<hr>") == "#line(length: 100%)"
}

pub fn blockquote_test() {
  assert html2typst.h2t("<blockquote>q</blockquote>")
    == "#quote(attribution: [none])[q]"
}

pub fn blockquote_with_cite_test() {
  assert html2typst.h2t("<blockquote cite=\"src\">q</blockquote>")
    == "#quote(attribution: [src])[q]"
}

pub fn unordered_list_test() {
  assert html2typst.h2t("<ul><li>a</li><li>b</li></ul>") == "- a\n- b"
}

pub fn ordered_list_test() {
  assert html2typst.h2t("<ol><li>a</li><li>b</li></ol>") == "+ a\n+ b"
}

pub fn nested_list_is_indented_test() {
  assert html2typst.h2t("<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>")
    == "- a\n  - b\n- c"
}

/// 字下げが階層ごとに積み上がること。depth を引数で持ち回らず、
/// 各階層が子の出力に indent を 1 回掛けるだけで 4 スペースになる。
pub fn deeply_nested_list_test() {
  assert html2typst.h2t(
      "<ul><li>a<ul><li>b<ol><li>c</li></ol></li></ul></li></ul>",
    )
    == "- a\n  - b\n    + c"
}

/// 入れ子のリストの中に空行が入ると Typst はそこでリストを終端してしまう。
pub fn nested_list_has_no_blank_lines_test() {
  assert html2typst.h2t("<ul><li><p>a</p><ul><li>b</li></ul></li></ul>")
    == "- a\n  - b"
}

// --- インライン要素 --------------------------------------------------------

pub fn strong_test() {
  assert html2typst.h2t("<p>a <strong>b</strong> c</p>") == "a *b* c"
}

pub fn em_test() {
  assert html2typst.h2t("<p>a <em>b</em> c</p>") == "a _b_ c"
}

pub fn nested_inline_markup_test() {
  assert html2typst.h2t("<p>a <strong><em>b</em></strong> c</p>") == "a *_b_* c"
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

// --- pre / code ------------------------------------------------------------
//
// raw の中身は escape も collapse_whitespace も通さない。
// 通すと `#` がバックスラッシュ付きでコードに混ざる。

pub fn inline_code_test() {
  assert html2typst.h2t("<p>use <code>x = 1</code> now</p>")
    == "use `x = 1` now"
}

/// インライン raw の中身は Typst のマークアップとして解釈されないので、
/// escape してはいけない。
pub fn inline_code_is_not_escaped_test() {
  assert html2typst.h2t("<p><code>a #b $c *d</code></p>") == "`a #b $c *d`"
}

/// 実体参照だけは戻す。raw_text が decode_entities を通しているため。
pub fn inline_code_decodes_entities_test() {
  assert html2typst.h2t("<p><code>&lt;div&gt;</code></p>") == "`<div>`"
}

pub fn pre_test() {
  assert html2typst.h2t("<pre>aaa\nbbb</pre>") == "```\naaa\nbbb\n```"
}

/// 一番よくある形。<pre> が直下の <code> を自分で覗きに行く。
pub fn pre_code_test() {
  assert html2typst.h2t("<pre><code>aaa\nbbb</code></pre>")
    == "```\naaa\nbbb\n```"
}

pub fn pre_code_language_class_test() {
  assert html2typst.h2t(
      "<pre><code class=\"language-rust\">fn main() {}</code></pre>",
    )
    == "```rust\nfn main() {}\n```"
}

pub fn pre_code_lang_prefix_test() {
  assert html2typst.h2t(
      "<pre><code class=\"lang-python\">print(1)</code></pre>",
    )
    == "```python\nprint(1)\n```"
}

/// class に語が複数あっても language- / lang- の付いたものだけ拾う。
pub fn pre_code_language_among_other_classes_test() {
  assert html2typst.h2t(
      "<pre><code class=\"language-rust hljs\">x</code></pre>",
    )
    == "```rust\nx\n```"
}

/// 言語を示さない class は無視して、言語なしの raw ブロックにする。
pub fn pre_code_without_language_class_test() {
  assert html2typst.h2t("<pre><code class=\"highlight\">plain</code></pre>")
    == "```\nplain\n```"
}

/// <pre> と <code> の間の空白テキストは pre_code の判定を邪魔しない。
pub fn pre_code_with_surrounding_whitespace_test() {
  assert html2typst.h2t("<pre>\n<code>x</code>\n</pre>") == "```\nx\n```"
}

/// <code> が 2 つ以上あるときは「pre 直下の code ひとつ」ではないので、
/// 言語判定はせず children 全体を平坦に畳む。
pub fn pre_with_multiple_code_children_test() {
  assert html2typst.h2t("<pre><code>a</code><code>b</code></pre>")
    == "```\nab\n```"
}

pub fn pre_decodes_entities_test() {
  assert html2typst.h2t("<pre><code>if a &gt; b &amp;&amp; c</code></pre>")
    == "```\nif a > b && c\n```"
}

/// raw_node が br を明示的に扱わないと、void 要素は children が空なので消える。
pub fn pre_keeps_line_breaks_test() {
  assert html2typst.h2t("<pre>a<br>b</pre>") == "```\na\nb\n```"
}

/// 行頭の字下げが保存されること。protect_significant_spaces が
/// タグ直後のスペースを &nbsp; に逃がしたぶんを decode_entities が戻す。
pub fn pre_keeps_indentation_test() {
  assert html2typst.h2t("<pre>  a\n    b</pre>") == "```\n  a\n    b\n```"
}

pub fn pre_is_separated_from_surrounding_blocks_test() {
  assert html2typst.h2t("<p>a</p><pre>code</pre><p>b</p>")
    == "a\n\n```\ncode\n```\n\nb"
}

pub fn inline_code_inside_list_item_test() {
  assert html2typst.h2t("<ul><li>a <code>c</code></li></ul>") == "- a `c`"
}

// --- 壊れやすいところ ------------------------------------------------------

pub fn unknown_tags_keep_their_content_test() {
  assert html2typst.h2t("<div><section><p>kept</p></section></div>") == "kept"
}

pub fn typst_special_characters_are_escaped_test() {
  assert html2typst.h2t("<p>a #b $c *d</p>") == "a \\#b \\$c \\*d"
}

pub fn more_typst_special_characters_are_escaped_test() {
  assert html2typst.h2t("<p>a\\b @c [d] `e`</p>")
    == "a\\\\b \\@c \\[d\\] \\`e\\`"
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

pub fn ignore_script_test() {
  assert html2typst.h2t("<script>console.log(\"hello\")</script>") == ""
}

// --- 未実装 -----------------------------------------------------------------
//
// 期待値は「あるべき出力」。実装がまだ追いついていないので現状は落ちる。
// 通したら上の pre / code セクションに移すこと。

/// raw ブロックの中の空行は原文どおり残さないといけない。
/// 現状は tidy の squeeze_blank_lines が中まで潰す。
pub fn pre_keeps_blank_lines_test() {
  assert html2typst.h2t("<pre>a\n\n\nb</pre>") == "```\na\n\n\nb\n```"
}

/// 中身にバックティックの 3 連続が含まれるときは、フェンス側を
/// 「中身の最長連続 + 1 本（最低 3 本）」に伸ばす。中身は一字一句そのまま。
/// 現状は 3 本固定なので、Typst 側で raw ブロックが途中で閉じて
/// 中身が 3 つの raw に割れる（typst 0.15.1 で確認）。
pub fn pre_widens_the_fence_to_avoid_collision_test() {
  assert html2typst.h2t("<pre>```x```</pre>") == "````\n```x```\n````"
}

/// <pre> 直後の改行 1 個は HTML 仕様どおり捨てるが、それに続く字下げは残す。
/// 末尾の改行 1 個も、閉じフェンスの改行と重なるので捨てる。
/// 現状は protect_significant_spaces がスペース 1 個しか守らないため、
/// 改行と字下げがまとめて落ちて末尾に空行が残る。
pub fn pre_keeps_indentation_after_a_leading_newline_test() {
  assert html2typst.h2t("<pre>\n  a\n</pre>") == "```\n  a\n```"
}
