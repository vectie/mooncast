///|
struct DeliveryCue {
  index : Int
  start_ms : Int
  end_ms : Int
  timestamp : String
  text : String
} derive(Debug, Eq)

///|
struct DeliveryTranscript {
  cues : Array[DeliveryCue]
  parse_error : String?
  query : String
  ready : Bool
  seconds : Double
  duration : Double
  media_error : String?
}

///|
fn empty_delivery_transcript() -> DeliveryTranscript {
  {
    cues: [],
    parse_error: None,
    query: "",
    ready: false,
    seconds: 0.0,
    duration: 0.0,
    media_error: None,
  }
}

///|
fn delivery_srt_number(text : StringView) -> Int? {
  guard !text.is_empty() && text.length() <= 8 else { return None }
  let mut value = 0
  for ch in text {
    guard ch >= '0' && ch <= '9' else { return None }
    value = value * 10 + ch.to_int() - 48
  }
  Some(value)
}

///|
fn delivery_srt_timestamp(text : String) -> Int? {
  guard text.length() == 12 &&
    text[2] == ':' &&
    text[5] == ':' &&
    text[8] == ',' else {
    return None
  }
  guard delivery_srt_number(text[:2]) is Some(hours) &&
    delivery_srt_number(text[3:5]) is Some(minutes) &&
    delivery_srt_number(text[6:8]) is Some(seconds) &&
    delivery_srt_number(text[9:]) is Some(ms) &&
    minutes < 60 &&
    seconds < 60 else {
    return None
  }
  Some(((hours * 60 + minutes) * 60 + seconds) * 1000 + ms)
}

///|
/// Completed-output SRT is already clipped and rebased. Never apply the source
/// master's in_seconds here. A malformed or over-limit file disables navigation
/// as a whole, while its exact raw preview and download remain available.
fn parse_delivery_transcript(
  content : String,
) -> Result[Array[DeliveryCue], String] {
  let invalid = "Caption navigation is unavailable: the SRT is empty, malformed, or exceeds 5,000 cues / 1,048,576 text units. The exact raw SRT remains below."
  guard content.length() <= 1048576 else { return Err(invalid) }
  let normalized = content.replace_all(old="\r\n", new="\n")
  let normalized = normalized
    .strip_prefix("\uFEFF")
    .unwrap_or(normalized[:])
    .to_owned()
  guard !normalized.contains("\r") else { return Err(invalid) }
  let lines = normalized.split("\n").map(StringView::to_owned).collect()
  let cues : Array[DeliveryCue] = []
  let mut cursor = 0
  while cursor < lines.length() {
    if lines[cursor].trim().is_empty() {
      cursor += 1
      continue
    }
    guard cues.length() < 5000 &&
      delivery_srt_number(lines[cursor].trim()) is Some(number) &&
      number > 0 else {
      return Err(invalid)
    }
    cursor += 1
    guard cursor < lines.length() else { return Err(invalid) }
    let times = lines[cursor]
      .split(" --> ")
      .map(s => s.trim().to_owned())
      .collect()
    guard times.length() == 2 &&
      delivery_srt_timestamp(times[0]) is Some(start_ms) &&
      delivery_srt_timestamp(times[1]) is Some(end_ms) &&
      start_ms < end_ms else {
      return Err(invalid)
    }
    cursor += 1
    let text : Array[String] = []
    while cursor < lines.length() && !lines[cursor].trim().is_empty() {
      text.push(lines[cursor])
      cursor += 1
    }
    guard !text.is_empty() else { return Err(invalid) }
    cues.push({
      index: cues.length(),
      start_ms,
      end_ms,
      timestamp: times[0],
      text: text.join("\n"),
    })
  }
  if cues.is_empty() {
    Err(invalid)
  } else {
    Ok(cues)
  }
}

///|
fn delivery_cue_active(
  cue : DeliveryCue,
  transcript : DeliveryTranscript,
) -> Bool {
  // End is exclusive; overlap may legitimately have multiple active cues.
  transcript.ready &&
  transcript.seconds >= cue.start_ms.to_double() / 1000.0 &&
  transcript.seconds < cue.end_ms.to_double() / 1000.0
}

///|
fn delivery_matching_cues(
  transcript : DeliveryTranscript,
) -> Array[DeliveryCue] {
  let query = transcript.query.trim().to_owned().to_lower()
  transcript.cues.filter(cue => {
    query.is_empty() ||
    cue.text.to_lower().contains(query) ||
    cue.timestamp.contains(query)
  })
}

///|
fn delivery_player_id(generation : Int) -> String {
  "completed-delivery-player-" + generation.to_string()
}

///|
fn invalidate_delivery_media(model : Model) -> Model {
  {
    ..model,
    delivery_media_selection: None,
    delivery_media_generation: model.delivery_media_generation + 1,
    delivery_caption_preview: None,
    delivery_caption_error: None,
    delivery_caption_loading: false,
    delivery_caption_identity: None,
    delivery_transcript: empty_delivery_transcript(),
  }
}

///|
fn receive_delivery_player_event(
  model : Model,
  generation : Int,
  kind : String,
  seconds : Double,
  duration : Double,
) -> Model {
  guard generation == model.delivery_media_generation &&
    model.tab == Delivery &&
    selected_delivery_video(model) is Some(_) else {
    return model
  }
  let transcript = model.delivery_transcript
  if kind == "error" || kind == "unavailable" {
    return {
      ..model,
      delivery_transcript: {
        ..transcript,
        ready: false,
        media_error: Some(
          "Playback metadata is unavailable. Retry video and SRT; raw captions and downloads remain available.",
        ),
      },
    }
  }
  if kind == "seek-error" {
    return {
      ..model,
      delivery_transcript: {
        ..transcript,
        media_error: Some(
          "The player could not seek. Try the cue again, or retry video and SRT.",
        ),
      },
    }
  }
  guard (kind == "metadata" || kind == "time" || kind == "seeked") &&
    cut_player_finite(seconds) &&
    cut_player_finite(duration) &&
    duration > 0.0 &&
    seconds >= 0.0 &&
    seconds <= duration &&
    !(transcript.media_error is Some(_) && !transcript.ready) else {
    return model
  }
  {
    ..model,
    delivery_transcript: {
      ..transcript,
      ready: true,
      seconds,
      duration,
      media_error: if kind == "seeked" {
        None
      } else {
        transcript.media_error
      },
    },
  }
}

///|
fn delivery_cue_seek_target(
  model : Model,
  generation : Int,
  index : Int,
) -> Int? {
  guard generation == model.delivery_media_generation &&
    model.tab == Delivery &&
    selected_delivery_video(model) is Some(_) &&
    model.delivery_transcript.ready &&
    model.delivery_transcript.parse_error is None &&
    model.delivery_transcript.cues.get(index) is Some(cue) &&
    cue.start_ms.to_double() / 1000.0 < model.delivery_transcript.duration else {
    return None
  }
  Some(cue.start_ms)
}

///|
fn delivery_cue_seek_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  generation : Int,
  index : Int,
) -> @rabbita.Cmd {
  guard delivery_cue_seek_target(model, generation, index) is Some(target) else {
    return @rabbita.none
  }
  @cmd.custom_cmd(
    scheduler => {
      delivery_player_dom_seek(delivery_player_id(generation), target, (
        kind,
        seconds,
        duration,
      ) => {
        scheduler.add(
          emit(DeliveryPlayerEvent(generation, kind, seconds, duration)),
        )
      })
    },
    kind=@cmd.after_render,
  )
}

///|
priv suberror DeliveryPlayerSubscription {
  WatchDeliveryPlayer(Int, @rabbita.Emit[Msg])
}

///|
fn delivery_player_subscriptions(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @sub.Sub {
  guard model.tab == Delivery && selected_delivery_video(model) is Some(_) else {
    return @sub.none
  }
  let generation = model.delivery_media_generation
  @sub.custom_sub(
    delivery_player_id(generation),
    Local,
    WatchDeliveryPlayer(generation, emit),
    @sub.SubLoader((payload, scheduler) => {
      guard payload is WatchDeliveryPlayer(generation, emit) else {
        return None
      }
      let cleanup = delivery_player_dom_watch(delivery_player_id(generation), (
        kind,
        seconds,
        duration,
      ) => {
        scheduler.add(
          emit(DeliveryPlayerEvent(generation, kind, seconds, duration)),
        )
      })
      Some({ unload: _ => cleanup(), update_tagger: _ => (), })
    }),
  )
}
