///|
pub(all) struct DeliveryOutputCaptions {
  content : String
  digest : String
  mapping : Json
} derive(Debug, Eq, ToJson, FromJson)

///|
fn caption_milliseconds(seconds : Double) -> Int raise {
  // SRT cannot represent sub-millisecond edits. Never silently round them.
  guard seconds >= 0.0 && seconds <= 2147483.0 else {
    fail(
      "Caption timing must be finite, nonnegative and within the SRT timeline.",
    )
  }
  let millis = seconds * 1000.0
  let rounded = millis.round()
  guard (millis - rounded).abs() < 0.000001 else {
    fail(
      "Caption cuts require whole-millisecond boundaries. Export a corrected cut in Cut Editor.",
    )
  }
  rounded.to_int()
}

///|
fn caption_clock(value : Int) -> String {
  fn pad(value : Int, width : Int) -> String {
    let mut text = value.to_string()
    while text.length() < width {
      text = "0" + text
    }
    text
  }
  pad(value / 3600000, 2) +
  ":" +
  pad(value / 60000 % 60, 2) +
  ":" +
  pad(value / 1000 % 60, 2) +
  "," +
  pad(value % 1000, 3)
}

///|
/// Derive captions only for the delivery model's identity or one contiguous
/// trim. Spatial variants preserve the master's clock. Text is taken solely
/// from the verified source SRT; this function never transcribes or translates.
/// The caller must validate the complete delivery profile (including source IDs)
/// and bind a canonical verified editor sidecar. Arbitrary imported SRT may be
/// normalized by the existing parser and is not interchangeable with that source.
pub fn delivery_output_captions(
  source : Bytes,
  master_duration_seconds : Double,
  output : @execution_domain.DeliveryOutputSpec,
) -> DeliveryOutputCaptions raise {
  let duration_ms = caption_milliseconds(master_duration_seconds)
  guard duration_ms > 0 && output.subtitle_mode == "sidecar" else {
    fail("A positive master duration and required sidecar are needed.")
  }
  let (start_ms, end_ms) = match output.kind {
    "source-master" | "platform-variant" => {
      guard output.in_seconds == None &&
        output.out_seconds == None &&
        output.timestamp_seconds == None &&
        output.source_output_id == None else {
        fail(
          "Caption mapping is unsupported. Export and promote this edited timeline in Cut Editor first.",
        )
      }
      (0, duration_ms)
    }
    "channel-cut" => {
      guard output.in_seconds is Some(start) &&
        output.out_seconds is Some(end) &&
        output.source_output_id is Some(_) &&
        output.timestamp_seconds == None else {
        fail(
          "Caption cuts need one contiguous source range; reordered, retimed and chained cuts require a new Cut Editor export.",
        )
      }
      let start_ms = caption_milliseconds(start)
      let end_ms = caption_milliseconds(end)
      guard end_ms > start_ms &&
        end_ms <= duration_ms &&
        end_ms - start_ms <= 180000 else {
        fail(
          "Caption cut must have positive duration, stay inside the master, and last at most 180 seconds.",
        )
      }
      (start_ms, end_ms)
    }
    _ => fail("This output has no supported caption timeline mapping.")
  }
  let parsed = @editor_media.parse_subtitles(
    source, "application/x-subrip", duration_ms, 1000,
  )
  let cue_mapping : Array[Json] = []
  let lines : Array[String] = []
  for cue in parsed.cues {
    let start = Int::max(cue.start_tick, start_ms)
    let finish = Int::min(cue.end_tick, end_ms)
    if finish > start {
      lines.append([
        (cue_mapping.length() + 1).to_string(),
        caption_clock(start - start_ms) +
        " --> " +
        caption_clock(finish - start_ms),
        cue.text,
        "",
      ])
      cue_mapping.push({
        "source_cue_id": cue.cue_id,
        "source_start_ms": cue.start_tick,
        "source_end_ms": cue.end_tick,
        "output_start_ms": start - start_ms,
        "output_end_ms": finish - start_ms,
        "text": cue.text,
      })
    }
  }
  guard !cue_mapping.is_empty() else {
    fail(
      "No verified caption cues overlap this cut. Choose a captioned range or export corrected captions in Cut Editor; required captions cannot be omitted.",
    )
  }
  let content = if output.kind == "channel-cut" {
    lines.join("\n")
  } else {
    @utf8.decode(source)
  }
  let digest = sha256(@utf8.encode(content))
  {
    content,
    digest,
    mapping: {
      "contract": "mooncast.delivery-caption-mapping.v1",
      "output_id": output.output_id,
      "source_output_id": output.source_output_id.unwrap_or("master"),
      "mapping": if output.kind == "channel-cut" {
        "contiguous-trim"
      } else {
        "identity"
      },
      "source_sha256": sha256(source),
      "sha256": digest,
      "source_in_ms": start_ms,
      "source_out_ms": end_ms,
      "duration_ms": end_ms - start_ms,
      "cue_count": cue_mapping.length(),
      "cues": cue_mapping,
      "boundary_policy": "half-open intersection; crossing cues clipped; zero-duration intersections omitted; subtract source_in_ms",
      "parser_version": parsed.parser_version,
      "derivation_version": "mooncast-contiguous-captions@1.0.0",
    },
  }
}
