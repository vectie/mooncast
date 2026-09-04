///|
suberror JsonKeyScanError {
  JsonKeyScanError(String)
} derive(Debug)

///|
fn skip_json_space(text : String, start : Int) -> Int {
  for cursor = start; cursor < text.length(); cursor = cursor + 1 {
    let unit = text[cursor]
    if unit != ' ' && unit != '\n' && unit != '\r' && unit != '\t' {
      return cursor
    }
  }
  text.length()
}

///|
fn json_string_end(text : String, start : Int) -> Int raise JsonKeyScanError {
  guard start < text.length() && text[start] == '"' else {
    raise JsonKeyScanError("expected JSON string")
  }
  let mut escaped = false
  for cursor in (start + 1)..<text.length() {
    let unit = text[cursor]
    if escaped {
      escaped = false
    } else if unit == '\\' {
      escaped = true
    } else if unit == '"' {
      return cursor + 1
    }
  }
  raise JsonKeyScanError("unterminated JSON string")
}

///|
fn decoded_json_key(
  text : String,
  start : Int,
  end : Int,
) -> String raise JsonKeyScanError {
  let value = @json.parse(text[start:end]) catch {
    _ => raise JsonKeyScanError("invalid JSON object key")
  }
  match value {
    Json::String(value) => value
    _ => raise JsonKeyScanError("JSON object key is not a string")
  }
}

///|
fn scan_json_value(
  text : String,
  start : Int,
  duplicates : Array[String],
) -> Int raise JsonKeyScanError {
  let cursor = skip_json_space(text, start)
  guard cursor < text.length() else {
    raise JsonKeyScanError("unexpected end of JSON value")
  }
  match text[cursor] {
    '{' => scan_json_object(text, cursor, duplicates)
    '[' => scan_json_array(text, cursor, duplicates)
    '"' => json_string_end(text, cursor)
    _ => {
      for end = cursor; end < text.length(); end = end + 1 {
        let unit = text[end]
        if unit == ',' ||
          unit == ']' ||
          unit == '}' ||
          unit == ' ' ||
          unit == '\n' ||
          unit == '\r' ||
          unit == '\t' {
          return end
        }
      }
      text.length()
    }
  }
}

///|
fn scan_json_object(
  text : String,
  start : Int,
  duplicates : Array[String],
) -> Int raise JsonKeyScanError {
  let seen : Map[String, Unit] = Map([])
  let mut cursor = skip_json_space(text, start + 1)
  if cursor < text.length() && text[cursor] == '}' {
    return cursor + 1
  }
  for ;; {
    guard cursor < text.length() && text[cursor] == '"' else {
      raise JsonKeyScanError("expected JSON object key")
    }
    let key_end = json_string_end(text, cursor)
    let key = decoded_json_key(text, cursor, key_end)
    if seen.contains(key) {
      duplicates.push(key)
    } else {
      seen[key] = ()
    }
    cursor = skip_json_space(text, key_end)
    guard cursor < text.length() && text[cursor] == ':' else {
      raise JsonKeyScanError("expected colon after JSON object key")
    }
    cursor = skip_json_space(
      text,
      scan_json_value(text, cursor + 1, duplicates),
    )
    guard cursor < text.length() else {
      raise JsonKeyScanError("unterminated JSON object")
    }
    if text[cursor] == '}' {
      return cursor + 1
    }
    guard text[cursor] == ',' else {
      raise JsonKeyScanError("expected comma in JSON object")
    }
    cursor = skip_json_space(text, cursor + 1)
  }
}

///|
fn scan_json_array(
  text : String,
  start : Int,
  duplicates : Array[String],
) -> Int raise JsonKeyScanError {
  let mut cursor = skip_json_space(text, start + 1)
  if cursor < text.length() && text[cursor] == ']' {
    return cursor + 1
  }
  for ;; {
    cursor = skip_json_space(text, scan_json_value(text, cursor, duplicates))
    guard cursor < text.length() else {
      raise JsonKeyScanError("unterminated JSON array")
    }
    if text[cursor] == ']' {
      return cursor + 1
    }
    guard text[cursor] == ',' else {
      raise JsonKeyScanError("expected comma in JSON array")
    }
    cursor = skip_json_space(text, cursor + 1)
  }
}

///|
fn duplicate_json_keys(text : String) -> Array[String] raise JsonKeyScanError {
  let duplicates : Array[String] = []
  let end = skip_json_space(text, scan_json_value(text, 0, duplicates))
  guard end == text.length() else {
    raise JsonKeyScanError("trailing content after JSON document")
  }
  duplicates
}
