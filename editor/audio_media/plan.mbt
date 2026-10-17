///|
/// An explicitly selected, already synchronized soundtrack. The original media
/// streams are preserved; only the imported soundtrack is encoded.
pub(all) struct Plan {
  media : @media.Media
  audio : @audio.AudioTrack
  dispositions : Array[Array[String]]
  language : String
  title : String
  codec : String
  rendition_suffix : String
  is_default : Bool
} derive(ToJson)

///|
pub extend Plan with ToJson::{to_json}

///|
fn dispositions(probe : Json, index : Int) -> Array[String] raise {
  guard probe is { "streams": Array(streams), .. } else {
    fail("missing stream dispositions")
  }
  for stream in streams {
    if stream
      is { "index": Number(found, ..), "disposition": Object(flags), .. } &&
      found == index.to_double() {
      let enabled : Array[String] = []
      for name, value in flags {
        guard !name.is_empty() &&
          name.iter().all(c => (c >= 'a' && c <= 'z') || c == '_') &&
          (value == Json::number(0) || value == Json::number(1)) else {
          fail("unsupported disposition metadata")
        }
        if value == Json::number(1) {
          enabled.push(name)
        }
      }
      enabled.sort_by((a, b) => a.lexical_compare(b))
      return enabled
    }
  }
  fail("missing stream dispositions")
}

///|
/// Preview a selectable language, commentary or audio-description track. This
/// validates declared timing; attach also measures the encoded selected stream
/// before muxing, since a container duration can hide a shorter selected track.
pub fn prepare(
  media_probe : Json,
  audio_probe : Json,
  index : Int,
  language : String,
  title : String,
) -> Plan raise {
  let media = @media.inspect_media(media_probe)
  let source = @audio.inspect_source(audio_probe)
  guard media.tracks.length() < 17 else { fail("no room for another track") }
  guard language.length() == 3 && language.iter().all(c => c >= 'a' && c <= 'z') else {
    fail("language must be a three-letter lowercase code; use und for unknown")
  }
  guard !title.is_blank() &&
    title.length() <= 120 &&
    title.iter().all(c => c >= ' ') else {
    fail("track title must contain 1–120 characters without controls")
  }
  guard (source.duration_ms - media.duration_ms.to_double()).abs() <= 50.0 else {
    fail(
      "soundtrack and media durations differ by more than 50 ms; synchronize externally first",
    )
  }
  guard source.audio_tracks.iter().find_first(t => t.index == index)
    is Some(audio) else {
    fail("choose a listed absolute audio stream index")
  }
  guard (audio.channels == 1 || audio.channels == 2) &&
    audio.start_ms.abs() <= 1.0 else {
    fail(
      "selected soundtrack must be zero-origin mono or stereo; no implicit downmix or shift",
    )
  }
  if audio.duration_ms is Some(duration) {
    guard (duration - media.duration_ms.to_double()).abs() <= 50.0 else {
      fail("selected audio duration differs from media by more than 50 ms")
    }
  }
  {
    media,
    audio,
    dispositions: media.tracks.map(t => dispositions(media_probe, t.index)),
    language,
    title,
    codec: if media.suffix == ".mp4" {
      "aac"
    } else {
      "flac"
    },
    rendition_suffix: if media.suffix == ".mp4" {
      ".m4a"
    } else {
      ".flac"
    },
    is_default: !media.tracks.any(t => t.kind == "audio"),
  }
}

///|
/// Verify the actual selected audio after encoding into its standalone file.
/// A shorter selected track in a longer container cannot silently pass this gate.
pub fn verify_rendition(plan : Plan, probe : Json) -> Unit raise {
  let source = @audio.inspect_source(probe)
  guard source.audio_tracks.length() == 1 && source.stream_indices.length() == 1 else {
    fail("encoded soundtrack must contain exactly one stream")
  }
  let audio = source.audio_tracks[0]
  let expected = plan.media.duration_ms.to_double()
  guard audio.codec == plan.codec &&
    audio.channels == plan.audio.channels &&
    audio.sample_rate == 48000 &&
    audio.start_ms.abs() <= 1.0 &&
    (source.duration_ms - expected).abs() <= 50.0 else {
    fail(
      "encoded selected soundtrack does not span the media or has an unexpected format",
    )
  }
  if audio.duration_ms is Some(duration) {
    guard (duration - expected).abs() <= 50.0 else {
      fail("encoded audio duration differs")
    }
  }
}
