import gleam/list

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

pub fn foo_test() {
  let _ = mul_str("-", 2)
}

fn long_list(x, i) {
  case i {
    0 -> x
    n ->
      case x {
        [head, ..tail] -> [head + 1, head, ..tail]
        [] -> []
      }
      |> long_list(n - 1)
  }
}

pub fn long_list_gene(i) {
  long_list([0], i) |> list.reverse()
}

pub fn bar_test() {
  let _long_list = long_list_gene(100) |> list.fold(0, fn(acc, x) { acc + x })
}
