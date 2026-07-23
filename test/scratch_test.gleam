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
