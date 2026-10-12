///|
fn quote(value : String) -> String {
  "\"" + value.replace_all(old="\"", new="\"\"") + "\""
}

///|
// Strict comma CSV with doubled quotes and multiline fields. Only a leading
// UTF-8 BOM and CRLF line endings are normalized; whitespace is never trimmed.
fn parse_csv(source : String) -> Array[Array[String]] raise {
  guard @utf8.encode(source).length() <= 16777216 else {
    fail("sheet exceeds 16 MiB")
  }
  let input = source.replace_all(old="\r\n", new="\n")
  let chars = input.iter().to_array()
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let mut field = StringBuilder()
  // 0 field start, 1 bare field, 2 quoted field, 3 after closing quote
  let mut state = 0
  let mut pending = false
  for i, char in chars {
    if i == 0 && char == '\u{feff}' {
      continue
    }
    guard char != '\r' else { fail("bare carriage return is unsupported") }
    if state == 2 {
      if char == '"' {
        state = 3
      } else {
        field.write_char(char)
      }
      pending = true
      continue
    }
    if state == 3 && char == '"' {
      field.write_char('"')
      state = 2
      continue
    }
    if char == ',' || char == '\n' {
      row.push(field.to_string())
      guard row.length() <= 5 else { fail("expected five CSV columns") }
      field = StringBuilder()
      state = 0
      pending = true
      if char == '\n' {
        rows.push(row)
        guard rows.length() <= 5001 else { fail("too many sheet rows") }
        row = []
        pending = false
      }
      continue
    }
    guard state != 3 else { fail("unexpected text after closing CSV quote") }
    if char == '"' {
      guard state == 0 else { fail("quote inside unquoted CSV field") }
      state = 2
    } else {
      field.write_char(char)
      state = 1
    }
    pending = true
  }
  guard state != 2 else { fail("unterminated quoted CSV field") }
  if pending {
    row.push(field.to_string())
    rows.push(row)
  }
  guard !rows.is_empty() && rows.length() <= 5001 else {
    fail("empty or oversized sheet")
  }
  for row in rows {
    guard row.length() == 5 else {
      fail("every CSV row must have five columns")
    }
  }
  rows
}
