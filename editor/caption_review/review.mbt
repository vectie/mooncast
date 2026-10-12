///|
/// A cue's exact before/after values, in original draft order.
pub(all) struct Change {
  cue_key : String
  before : @captions.Caption
  after : @captions.Caption
} derive(Eq, Debug, ToJson)

///|
/// A new validated draft and only the cues that changed. The source is untouched.
pub(all) struct Review {
  draft : @captions.CaptionDraft
  changes : Array[Change]
} derive(Eq, Debug, ToJson)

///|
/// Semantic binding: JSON formatting and object key order do not invalidate it.
/// It is an integrity check, not an author identity or approval receipt.
pub fn binding(draft : @captions.CaptionDraft) -> String raise {
  draft.validate()
  "sha256:" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(draft.to_json().stringify())),
  )
}

///|
fn key(index : Int) -> String {
  "cue-" + (index + 1).to_string()
}

///|
/// Export a keyed sheet. Keep source_binding/cue_key unchanged and edit the
/// millisecond columns or text after its literal text: prefix. Quoted newlines
/// are caption line breaks; text: prevents spreadsheet formula interpretation.
pub fn export_sheet(draft : @captions.CaptionDraft) -> String raise {
  let source_binding = binding(draft)
  let out = StringBuilder()
  out.write_string("source_binding,cue_key,start_ms,end_ms,text\n")
  for i, cue in draft.cues {
    out.write_string(
      [
        source_binding,
        key(i),
        cue.start_ms.to_string(),
        cue.end_ms.to_string(),
        "text:" + cue.text,
      ]
      .map(quote)
      .join(",") +
      "\n",
    )
  }
  let sheet = out.to_string()
  guard @utf8.encode(sheet).length() <= 16777216 else {
    fail("sheet exceeds 16 MiB")
  }
  sheet
}

///|
fn milliseconds(value : String) -> Int raise {
  guard !value.is_empty() && value.iter().all(c => c >= '0' && c <= '9') else {
    fail(
      "times must be whole nonnegative milliseconds, without spaces or units",
    )
  }
  @string.parse_int(value)
}

///|
/// Apply all keyed changes together, not sequential single-cue edits. Every
/// original key is required exactly once; row order does not reorder captions.
/// Invalid text, timing, stale binding or keys rejects the entire operation.
pub fn apply_sheet(
  draft : @captions.CaptionDraft,
  sheet : String,
) -> Review raise {
  let expected = binding(draft)
  let rows = parse_csv(sheet)
  guard rows[0] == ["source_binding", "cue_key", "start_ms", "end_ms", "text"] else {
    fail("unsupported review sheet header; export a new sheet")
  }
  guard rows.length() == draft.cues.length() + 1 else {
    fail("sheet must contain every original cue exactly once")
  }
  let by_key : Map[String, @captions.Caption] = Map([])
  let allowed : Map[String, Bool] = Map([])
  for i in 0..<draft.cues.length() {
    allowed[key(i)] = true
  }
  for row in rows[1:] {
    guard row[0] == expected else {
      fail("sheet belongs to a different draft revision")
    }
    guard allowed.contains(row[1]) else { fail("unknown cue key: " + row[1]) }
    guard !by_key.contains(row[1]) else { fail("duplicate cue key: " + row[1]) }
    guard row[4].has_prefix("text:") else {
      fail("keep the literal text: prefix in each text cell")
    }
    by_key[row[1]] = {
      start_ms: milliseconds(row[2]),
      end_ms: milliseconds(row[3]),
      text: row[4][5:].to_owned(),
    }
  }
  let cues : Array[@captions.Caption] = []
  let changes : Array[Change] = []
  for i, before in draft.cues {
    let cue_key = key(i)
    guard by_key.get(cue_key) is Some(after) else {
      fail("missing cue: " + cue_key)
    }
    cues.push(after)
    if before != after {
      changes.push({ cue_key, before, after, })
    }
  }
  let updated = { ..draft, cues, }
  updated.validate()
  { draft: updated, changes, }
}
