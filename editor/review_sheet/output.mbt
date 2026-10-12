///|
fn escape_html(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///|
fn pad(value : Int, width : Int) -> String {
  let text = value.to_string()
  "0".repeat(width - text.length()) + text
}

///|
pub fn time(ms : Int) -> String {
  pad(ms / 3600000, 2) +
  ":" +
  pad(ms / 60000 % 60, 2) +
  ":" +
  pad(ms / 1000 % 60, 2) +
  "." +
  pad(ms % 1000, 3)
}

///|
/// Standalone responsive/printable HTML using only relative generated PNGs.
/// No script, network, original absolute path or embedded media is needed.
pub fn Sheet::html(
  self : Sheet,
  source_name : String,
  source_sha256 : String,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>" +
    escape_html(self.title) +
    "</title>\n",
  )
  out.write_string(
    "<style>body{margin:0;background:#f4f3ef;color:#172126;font:16px/1.5 system-ui,sans-serif}header,nav,main,footer{max-width:1200px;margin:auto;padding:1.2rem}h1{margin:0}a{color:#005a75}:focus-visible{outline:3px solid #be5500;outline-offset:3px}nav ol{display:flex;gap:1rem;flex-wrap:wrap;padding-left:1.5rem}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,320px),1fr));gap:1.2rem}article{background:white;border:1px solid #b7c4c7;padding:1rem;border-radius:8px;break-inside:avoid}h2{font-size:1.15rem;margin-top:0}figure{margin:0}img{width:100%;height:auto;display:block}figcaption,.timing{font-size:.9rem}p{overflow-wrap:anywhere}.words{white-space:pre-wrap}.note{border-top:1px solid #aaa;min-height:3em;margin-top:1rem}.muted{color:#45565d}@media print{body{background:white;font-size:10pt}nav,.skip{display:none}.grid{grid-template-columns:1fr 1fr}article{border-radius:0}a{color:inherit;text-decoration:none}header,main,footer{padding:.4rem}.note{min-height:2em}img{max-height:5cm;object-fit:contain}}</style></head><body>\n",
  )
  out.write_string(
    "<a class=\"skip\" href=\"#sheet\">Skip navigation</a><header><h1>" +
    escape_html(self.title) +
    "</h1><p>" +
    escape_html(source_name) +
    " · " +
    time(self.duration_ms) +
    " · " +
    self.cards.length().to_string() +
    " samples</p><p class=\"muted\">Visual sampling sheet. Each image is requested at the interval midpoint; the next decoded frame can differ by a frame or more. Short shots may be missed. Caption excerpts cover the whole interval and may repeat across cards.</p><p class=\"muted\">Local review aid. Inspect the full video for motion, audio, caption timing and editorial decisions. No client acceptance or delivery is recorded.</p></header>\n<nav aria-label=\"Sample navigation\"><ol>\n",
  )
  for card in self.cards {
    out.write_string(
      "<li><a href=\"#card-" +
      card.number.to_string() +
      "\">" +
      escape_html(card.title) +
      "</a></li>\n",
    )
  }
  out.write_string("</ol></nav><main id=\"sheet\" class=\"grid\">\n")
  for card in self.cards {
    let n = card.number.to_string()
    out.write_string(
      "<article aria-labelledby=\"card-" +
      n +
      "\"><h2 id=\"card-" +
      n +
      "\">" +
      n +
      ". " +
      escape_html(card.title) +
      "</h2><p class=\"timing\">Interval " +
      time(card.start_ms) +
      "–" +
      time(card.end_ms) +
      "</p><figure><a href=\"" +
      card.image +
      "\"><img src=\"" +
      card.image +
      "\" width=\"640\" height=\"360\" alt=\"Video sample requested at " +
      time(card.requested_ms) +
      "; " +
      escape_html(card.title) +
      "\"></a><figcaption>Requested at " +
      time(card.requested_ms) +
      "</figcaption></figure>\n",
    )
    if card.excerpts.is_empty() {
      out.write_string(
        if self.has_captions {
          "<p class=\"muted\">No supplied caption overlaps this interval.</p>\n"
        } else {
          "<p class=\"muted\">No caption draft supplied.</p>\n"
        },
      )
    } else {
      out.write_string("<details open><summary>Caption excerpts</summary>\n")
      for cue in card.excerpts {
        out.write_string(
          "<p class=\"timing\">Cue " +
          cue.cue_number.to_string() +
          " · " +
          time(cue.start_ms) +
          "–" +
          time(cue.end_ms) +
          "</p><p class=\"words\">" +
          escape_html(cue.text) +
          "</p>\n",
        )
      }
      out.write_string("</details>\n")
    }
    out.write_string(
      "<div class=\"note\">Review notes (print):</div></article>\n",
    )
  }
  out.write_string(
    "</main><footer><p>Source SHA-256: " +
    escape_html(source_sha256) +
    "</p><p>Keep this entire folder together. Source media is not copied; the images and caption excerpts remain readable offline.</p></footer></body></html>\n",
  )
  out.to_string()
}
