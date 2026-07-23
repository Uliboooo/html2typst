//// HTML を Typst のマークアップに変換する。
////
//// 処理は 3 段階に分かれている:
////
////   1. html_parser.as_list  … HTML を平坦な Element の列にする（外部ライブラリ）
////   2. parse                … その列から Node の木を組み立てる（このファイル）
////   3. render_node          … 木を Typst 文字列に変換する（このファイル）
////
//// 実装を足すときに触るのはほぼ 3 の `render_element` だけ。
//// 2 はタグの種類に依存しないので、基本的にそのままで動く。

import argv
import filepath
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import html_parser
import simplifile

// ---------------------------------------------------------------------------
// Express Tree
// ---------------------------------------------------------------------------

/// html_parser.Element は「開始タグ」「終了タグ」を別々の値として持つ平坦な型。
/// 変換の都合が悪いので、子を内側に持つ木として組み直したものがこの Node。
pub type Node {
  /// 要素。children に子ノードが入る。
  Element(
    tag: String,
    attributes: List(html_parser.Attribute),
    children: List(Node),
  )
  /// テキスト。まだエスケープもエンティティ展開もしていない生の文字列。
  Text(String)
}

/// 閉じタグを持たない要素（void element）。
/// これを木に組むときに特別扱いしないと、後続の兄弟が全部この要素の
/// 子になってしまう。html_parser.as_tree はまさにそのバグを持っている。
fn is_void(tag: String) -> Bool {
  case tag {
    "area"
    | "base"
    | "br"
    | "col"
    | "embed"
    | "hr"
    | "img"
    | "input"
    | "link"
    | "meta"
    | "source"
    | "track"
    | "wbr" -> True
    _ -> False
  }
}

// ---------------------------------------------------------------------------
// 2. flat tree -> tree
// ---------------------------------------------------------------------------

/// HTML 文字列を Node の一覧にする。
/// トップレベルに複数の要素があってもよい（`<h2>a</h2><p>b</p>` など）。
pub fn parse(html: String) -> List(Node) {
  html
  |> protect_significant_spaces
  |> terminate_trailing_text
  |> html_parser.as_list
  |> parse_forest
}

/// html_parser はタグで終わらない入力の末尾テキストを落とす。
/// `"<p>a<p>b"` の "b" や `"a</span>b"` の "b" が消える。
/// 末尾に番兵の閉じタグを足して、必ずタグで終わる形にしておく。
/// 対応する開始タグが無い閉じタグは parse_forest が捨てるので害はない。
fn terminate_trailing_text(html: String) -> String {
  html <> "</html2typst-eof>"
}

/// html_parser は「タグの直後にある空白」を捨ててしまう。
/// `</strong> world` が Content("world") になり、`*強調*と` のように
/// 単語がくっつく。as_list を受け取った時点では情報が消えているので、
/// パーサに渡す前に実体参照へ逃がしておく（後で decode_entities が戻す）。
///
/// NOTE: 空白 1 個だけを対象にしている。タグの直後が改行やタブの場合は
///       今も落ちる。整形された HTML では `<p>あ\n<strong>い</strong></p>`
///       が該当する。厳密にやるなら html_parser を使わず自前で字句解析する。
fn protect_significant_spaces(html: String) -> String {
  string.replace(html, "> ", ">&nbsp;")
}

fn parse_forest(in: List(html_parser.Element)) -> List(Node) {
  case parse_siblings(in) {
    #(nodes, []) -> nodes
    // 誰にも対応しない閉じタグが残った場合は捨てて先に進む
    #(nodes, [_stray_end_tag, ..rest]) -> list.append(nodes, parse_forest(rest))
  }
}

/// 兄弟ノードを、入力が尽きるか閉じタグに当たるまで読む。
/// 戻り値は #(読めたノード, 未消費の入力)。
/// 閉じタグが自分のものかどうかは呼び出し側が判断する。
fn parse_siblings(
  in: List(html_parser.Element),
) -> #(List(Node), List(html_parser.Element)) {
  case in {
    [] -> #([], [])

    // 閉じタグ。ここで打ち切って呼び出し側に返す。
    [html_parser.EndElement(_), ..] -> #([], in)

    [html_parser.EmptyElement, ..rest] -> parse_siblings(rest)

    [html_parser.Content(text), ..rest] -> {
      let #(siblings, remaining) = parse_siblings(rest)
      #([Text(text), ..siblings], remaining)
    }

    [html_parser.StartElement(name, attrs, _), ..rest] ->
      case is_void(name) {
        // 閉じタグを持たない要素。子を読まずに次の兄弟へ。
        True -> {
          let #(siblings, remaining) = parse_siblings(rest)
          #([Element(name, attrs, []), ..siblings], remaining)
        }
        False -> {
          // まず子を読む
          let #(children, after_children) = parse_siblings(rest)
          // 自分の閉じタグなら消費する。違うタグならそのまま親に返す
          // （閉じ忘れ HTML でも落ちないようにするため）。
          let after_close = case after_children {
            [html_parser.EndElement(end_name), ..tail] if end_name == name ->
              tail
            _ -> after_children
          }
          let #(siblings, remaining) = parse_siblings(after_close)
          #([Element(name, attrs, children), ..siblings], remaining)
        }
      }
  }
}

// ---------------------------------------------------------------------------
// 3. Tree -> Typst
// ---------------------------------------------------------------------------

/// entory point
pub fn h2t(html: String) -> String {
  html |> parse |> render_nodes |> tidy
}

fn render_nodes(nodes: List(Node)) -> String {
  nodes |> list.map(render_node) |> string.concat
}

fn render_node(node: Node) -> String {
  case node {
    // NOTE: <pre> / <code> を実装するときは、この 3 つの加工を通さずに
    //       生のテキストを取り出す別経路が必要になる。
    Text(text) -> text |> decode_entities |> collapse_whitespace |> escape
    Element(tag, attributes, children) ->
      render_element(tag, attributes, children)
  }
}

/// raw ブロック用にテキストだけを取り出す。
/// escape も collapse_whitespace も掛けず、実体参照だけ戻す。
fn raw_text(nodes: List(Node)) -> String {
  nodes |> list.map(raw_node) |> string.concat
}

fn raw_node(node: Node) -> String {
  case node {
    Text(text) -> decode_entities(text)
    // void 要素は children が空なので、明示しないと消える
    Element("br", _, _) -> "\n"
    Element(_tag, _attributes, children) -> raw_text(children)
  }
}

fn how_much_bq(in: String) -> Int {
  let l =
    in
    |> string.to_graphemes
    |> list.take_while(fn(ch) { ch == "`" })
    |> list.length()
  l
}

/// class="language-rust" / "lang-rust" / "highlight language-rust" に対応。
fn language(attributes: List(html_parser.Attribute)) -> String {
  case attribute(attributes, "class") {
    Error(Nil) -> ""
    Ok(class) ->
      class
      |> string.split(" ")
      |> list.find_map(fn(c) {
        case c {
          "language-" <> lang -> Ok(lang)
          "lang-" <> lang -> Ok(lang)
          _ -> Error(Nil)
        }
      })
      |> result.unwrap("")
  }
}

/// <pre> の直下が実質 <code> ひとつだけか。
/// markdown / pandoc 由来の HTML はほぼこの形になる。
fn pre_code(
  children: List(Node),
) -> Result(#(List(html_parser.Attribute), List(Node)), Nil) {
  case list.filter(children, is_meaningful) {
    [Element("code", attrs, code_children)] -> Ok(#(attrs, code_children))
    _ -> Error(Nil)
  }
}

fn is_meaningful(node: Node) -> Bool {
  case node {
    Text(t) -> string.trim(t) != ""
    _ -> True
  }
}

fn multi_str(b, s, i: Int) {
  case i {
    0 -> s
    n -> multi_str(b, s <> b, n - 1)
  }
}

fn mul_str(s, i) {
  case i <= 0 {
    True -> ""
    False -> multi_str(s, s, i - 1)
  }
}

/// ここが変換表の本体。タグを増やすときはこの case に節を足す。
///
/// 実装済みのものは「形」ごとに 1 つずつ選んである:
///
///   p        ブロック要素
///   h1 / h2  ブロック要素 + 行頭の記号
///   ul       子（li）を自分で見に行く構造もの
///   strong   インラインの囲み
///   a        属性を使うもの
///   br       子を持たない要素
///   その他   中身だけ出して自分は消える（unwrap）
///
fn render_element(
  tag: String,
  attributes: List(html_parser.Attribute),
  children: List(Node),
) -> String {
  case tag {
    // --- ブロック要素 -------------------------------------------------
    "p" -> block(render_nodes(children))

    "h1" -> block("#title[" <> render_nodes(children) <> "]")
    "h2" -> block("= " <> render_nodes(children))
    "h3" -> block("== " <> render_nodes(children))
    "h4" -> block("=== " <> render_nodes(children))
    "h5" -> block("==== " <> render_nodes(children))
    "h6" -> block("===== " <> render_nodes(children))

    // 子の li を自分で拾う。marker を変えれば ol になる。
    // 空行を足す block() を被せるのはトップレベルのリストだけ。
    // 入れ子のぶんは render_list_item が字下げして中に埋める。
    "ul" -> block(render_list("-", children))
    "ol" -> block(render_list("+", children))

    // TODO: "blockquote" -> Typst の #quote[...]
    "blockquote" ->
      block(
        "#quote(attribution: ["
        <> case attribute(attributes, "cite") {
          Ok(cite) -> cite
          Error(_) -> "none"
        }
        <> "])["
        <> render_nodes(children)
        <> "]",
      )
    "hr" -> block("#line(length: 100%)")
    "pre" -> {
      let #(lang, body) = case pre_code(children) {
        Ok(#(attrs, code_children)) -> #(language(attrs), code_children)
        // <pre> 直下が生テキストの場合。言語は不明。
        Error(Nil) -> #("", children)
      }
      let raw = raw_text(body)
      let bq =
        how_much_bq(raw)
        |> fn(x) {
          case x {
            0 -> "```"
            n -> mul_str("`", n + 1)
          }
        }
      block(bq <> lang <> "\n" <> raw_text(body) <> "\n" <> bq)
    }

    // TODO: "table" -> #table(columns: N, ...) 列数を数える必要がある
    // --- インライン要素 -----------------------------------------------
    "strong" -> "*" <> render_nodes(children) <> "*"

    "em" -> "_" <> render_nodes(children) <> "_"
    "code" -> "`" <> raw_text(children) <> "`"
    // 属性を使う例。href が無いときはリンクにせず中身だけ出す。
    "a" ->
      case attribute(attributes, "href") {
        Ok(href) ->
          "#link(\"" <> href <> "\")[" <> render_nodes(children) <> "]"
        Error(Nil) -> render_nodes(children)
      }

    // TODO: "img" -> #image("src")。alt は #figure の caption に回せる
    // --- 子を持たない要素 ---------------------------------------------
    // Typst の強制改行は行末のバックスラッシュ。
    "br" -> "\\\n"

    "script" -> ""

    // --- 未知のタグ ---------------------------------------------------
    // div / span / body のような「構造だけ」のタグはここに落ちる。
    // 捨てずに中身を通すのが重要。捨てると本文が黙って消える。
    _ -> render_nodes(children)
  }
}

/// li だけを拾って marker を付ける。ul / ol で共用する。
/// 空行は入れない。Typst は空行でリストを終端するので、ここで入れると
/// 入れ子が「別のリスト」に割れてしまう。
fn render_list(marker: String, children: List(Node)) -> String {
  children
  |> list.filter_map(fn(child) {
    case child {
      Element("li", _, li_children) -> Ok(render_list_item(marker, li_children))
      // li 以外（要素間の空白テキストなど）は捨てる
      _ -> Error(Nil)
    }
  })
  |> string.join("\n")
}

/// li 1 個ぶん。中身に ul / ol があれば字下げして下にぶら下げる。
///
/// 深さを引数で持ち回らなくていいのは、各階層が自分の子の出力に 1 回ずつ
/// indent を掛けるから。3 階層目は 2 階層目の indent も重ねて受けるので、
/// 勝手に 4 スペースになる。
fn render_list_item(marker: String, li_children: List(Node)) -> String {
  // childがlistならnested, そうでないならinlineへ
  let #(nested, inline) = list.partition(li_children, is_list)

  // <li><p>…</p></li> のとき render_nodes が block() の空行を返すので落とす。
  // li の中に複数のブロックが並ぶ場合は今も崩れる。
  let head = marker <> " " <> string.trim(render_nodes(inline))

  case nested {
    [] -> head
    _ -> head <> "\n" <> indent(render_nested_lists(nested))
  }
}

fn is_list(node: Node) -> Bool {
  case node {
    Element("ul", _, _) | Element("ol", _, _) -> True
    _ -> False
  }
}

/// 入れ子のリスト。render_node 経由にすると render_element が block() を
/// 被せてしまうので、render_list を直接呼ぶ。
fn render_nested_lists(nodes: List(Node)) -> String {
  nodes
  |> list.filter_map(fn(node) {
    case node {
      Element("ol", _, children) -> Ok(render_list("+", children))
      Element("ul", _, children) -> Ok(render_list("-", children))
      // is_list を通しているのでここには来ない
      _ -> Error(Nil)
    }
  })
  |> string.join("\n")
}

fn indent(text: String) -> String {
  text
  |> string.split("\n")
  |> list.map(fn(l) { "  " <> l })
  |> string.join("\n")
}

// ---------------------------------------------------------------------------
// 補助
// ---------------------------------------------------------------------------

/// ブロック要素を空行で挟む。Typst の段落区切りは空行。
/// 前後の両方に入れるのは、閉じ忘れなどでブロックが入れ子になったときに
/// 前の内容とくっつかないようにするため。余分な空行は tidy が潰す。
fn block(rendered: String) -> String {
  "\n\n" <> rendered <> "\n\n"
}

/// 属性を名前で引く。
fn attribute(
  attributes: List(html_parser.Attribute),
  key: String,
) -> Result(String, Nil) {
  attributes
  |> list.find_map(fn(attr) {
    case attr {
      html_parser.Attribute(k, v) if k == key -> Ok(v)
      _ -> Error(Nil)
    }
  })
}

/// Typst のマークアップで意味を持つ文字を無効化する。
/// これを通さないと `#` や `$` を含む本文が Typst のコンパイルエラーになる。
fn escape(text: String) -> String {
  text
  // バックスラッシュを最初に処理する。後回しにすると、後段で足した
  // バックスラッシュを二重にエスケープしてしまう。
  |> string.replace("\\", "\\\\")
  |> string.replace("*", "\\*")
  |> string.replace("_", "\\_")
  |> string.replace("`", "\\`")
  |> string.replace("$", "\\$")
  |> string.replace("#", "\\#")
  |> string.replace("@", "\\@")
  |> string.replace("<", "\\<")
  |> string.replace(">", "\\>")
  |> string.replace("[", "\\[")
  |> string.replace("]", "\\]")
  // TODO: 行頭の "-" "+" "=" "/" もリスト・見出し・コメントとして
  //       解釈される。厳密にやるなら行単位の処理が要る。
}

/// HTML の実体参照を戻す。
fn decode_entities(text: String) -> String {
  text
  |> string.replace("&lt;", "<")
  |> string.replace("&gt;", ">")
  |> string.replace("&quot;", "\"")
  |> string.replace("&#39;", "'")
  |> string.replace("&nbsp;", " ")
  // &amp; は最後。先にやると "&amp;lt;" が "<" になってしまう。
  |> string.replace("&amp;", "&")
  // TODO: &#123; 形式の数値参照
}

/// HTML では連続する空白・改行は 1 個のスペースと同じ扱いなので潰す。
fn collapse_whitespace(text: String) -> String {
  let collapsed =
    text
    |> string.replace("\n", " ")
    |> string.replace("\t", " ")
    |> string.replace("  ", " ")
  case collapsed == text {
    True -> text
    False -> collapse_whitespace(collapsed)
  }
}

/// ブロックが入れ子になると空行が増えるので、最後にまとめて整える。
/// 行末の空白も落とす（要素の隙間に入った空白が空行として残るため）。
fn tidy(rendered: String) -> String {
  rendered
  |> string.split("\n")
  |> list.map(string.trim_end)
  |> string.join("\n")
  |> squeeze_blank_lines
  |> string.trim
}

fn squeeze_blank_lines(rendered: String) -> String {
  let squeezed = string.replace(rendered, "\n\n\n", "\n\n")
  case squeezed == rendered {
    True -> rendered
    False -> squeeze_blank_lines(squeezed)
  }
}

fn read(path) {
  case simplifile.read(from: path) {
    Ok(content) -> content
    Error(error) -> {
      echo error
      "error"
    }
  }
}

pub fn stem(path) -> String {
  filepath.base_name(path)
  |> filepath.strip_extension
}

fn resolve_custom(source, custom_path) {
  let import_se =
    list.map(custom_path, fn(p) {
      "#import "
      <> "\""
      <> p
      <> "\": "
      <> stem(p)
      <> "\n"
      <> "#show: "
      <> stem(p)
      <> "\n"
    })
    |> string.join("\n")
  import_se <> "\n" <> source
}

fn resolve_args() {
  case argv.load().arguments {
    [_, ..tail] -> tail
    n -> n
  }
}

fn write(content, path) {
  simplifile.write(contents: content, to: path)
}

fn resolve_write_path(path) {
  filepath.directory_name(path) <> "/" <> stem(path) <> ".typ"
}

pub fn main() -> Nil {
  echo resolve_args()
  // let contents = resolve_input_files_path(argv.load().arguments)

  argv.load().arguments
  |> list.map(fn(path) { #(read(path), path) })
  |> list.map(fn(read_content) { #(h2t(read_content.0), read_content.1) })
  |> list.map(fn(t) { #(resolve_custom(t.0, ["./config/config.typ"]), t.1) })
  |> list.map(fn(res) {
    case write(res.0, resolve_write_path(res.1)) {
      Ok(_) -> io.println("write to " <> resolve_write_path(res.1))
      Error(e) -> io.print_error(string.inspect(e))
    }
  })
  Nil
}
