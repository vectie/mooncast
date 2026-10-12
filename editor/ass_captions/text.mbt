///|
// Preserve visible text, flatten override/comment blocks, decode ASS escapes.
// Drawing mode is refused rather than misreading vector commands as dialogue.
fn plain_text(text : String, default_wrap : Int) -> (String, Bool) raise {
  let chars = text.iter().to_array()
  let out = StringBuilder()
  let mut wrap = default_wrap
  let mut overridden = false
  for i = 0; i < chars.length(); {
    let char = chars[i]
    if char == '{' {
      overridden = true
      let block = StringBuilder()
      let mut end = i + 1
      while end < chars.length() && chars[end] != '}' {
        guard chars[end] != '{' else {
          fail("nested ASS override blocks are unsupported")
        }
        block.write_char(chars[end])
        end += 1
      }
      guard end < chars.length() else { fail("unclosed ASS override block") }
      for token in block.to_string().split("\\").drop(1) {
        let tag = token.trim().to_string()
        if tag.has_prefix("p") &&
          !tag.has_prefix("pos") &&
          !tag.has_prefix("pbo") {
          guard tag == "p0" else {
            fail(
              "ASS drawing mode is unsupported; export text-only dialogue first",
            )
          }
        }
        if tag.has_prefix("q") {
          guard tag == "q0" || tag == "q1" || tag == "q2" || tag == "q3" else {
            fail("unsupported ASS wrap override")
          }
          wrap = decimal(tag[1:].to_string())
        }
        if tag.has_prefix("r") {
          wrap = default_wrap
        }
      }
      continue end + 1
    }
    guard char != '}' else { fail("unmatched ASS closing brace") }
    if char == '\\' && i + 1 < chars.length() {
      match chars[i + 1] {
        'N' => {
          out.write_char('\n')
          continue i + 2
        }
        'n' => {
          out.write_char(if wrap == 2 { '\n' } else { ' ' })
          continue i + 2
        }
        'h' => {
          out.write_char('\u{00a0}')
          continue i + 2
        }
        _ => ()
      }
    }
    out.write_char(char)
    continue i + 1
  }
  (out.to_string(), overridden)
}
