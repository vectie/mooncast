///|
async fn file_identity(path : String) -> (Int64, String) {
  guard @fs.exists(path) && @fs.kind(path) is Regular else {
    fail("expected local regular file: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= 1073741824L else {
    fail("media file must be 1 byte..1 GiB")
  }
  let hash = @crypto.SHA256::new()
  let mut offset = 0L
  while offset < size {
    let count = if size - offset > 1048576L {
      1048576
    } else {
      (size - offset).to_int()
    }
    hash.update(file.read_exactly_at(count, position=offset))
    offset += count.to_int64()
  }
  guard file.size() == size else { fail("source changed while hashing") }
  (size, @crypto.bytes_to_hex_string(hash.finalize()))
}

///|
fn digest(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn parent_path(path : String) -> String {
  let parts = path.split("/").map(p => p.to_string()).collect()
  ignore(parts.pop())
  if parts.is_empty() {
    "."
  } else if parts.length() == 1 && parts[0] == "" {
    "/"
  } else {
    parts.join("/")
  }
}

///|
async fn recipe_source_path(parent : String, path : String) -> String {
  @fs.realpath(if path.has_prefix("/") { path } else { parent + "/" + path })
}

///|
async fn render_recipe(
  recipe_path : String,
  prefix : String,
  from_record? : Bool = false,
) -> Unit {
  let input_limit = if from_record { 33554432 } else { 1048576 }
  let recipe_bytes = local_file(recipe_path, input_limit)
  let saved_sources : Array[Json] = []
  let recipe = if from_record {
    guard @json.parse(@utf8.decode(recipe_bytes))
      is {
        "contract": String("mooncast.multi-source-reel-delivery.v1"),
        "recipe": recipe,
        "sources": Array(sources),
        ..
      } else {
      fail("expected a multi-source reel edit record")
    }
    saved_sources.append(sources)
    @render.parse_reel_recipe(recipe.stringify())
  } else {
    @render.parse_reel_recipe(@utf8.decode(recipe_bytes))
  }
  guard !from_record || saved_sources.length() == recipe.sources.length() else {
    fail("edit record source identities are incomplete")
  }
  let parent = parent_path(@fs.realpath(recipe_path))
  guard !prefix.is_empty() &&
    !prefix.contains(":") &&
    !prefix.iter().any(c => c < ' ') else {
    fail("invalid local output prefix")
  }
  let output_parent = @fs.realpath(parent_path(prefix))
  let name = prefix.split("/").last().unwrap().to_string()
  guard !name.is_empty() && name != "." && name != ".." else {
    fail("invalid output filename")
  }
  let output = output_parent + "/" + name
  let existing_names = @fs.readdir(output_parent, include_hidden=true)
  for suffix in [".mp4", ".srt", ".json"] {
    guard !existing_names.contains(name + suffix) else {
      fail("output exists; choose a fresh prefix")
    }
  }
  let inputs : Array[String] = []
  let transcripts = []
  let audio : Array[Bool] = []
  let identities : Array[Json] = []
  let hashes : Array[(Int64, String)] = []
  let transcript_paths : Array[String] = []
  let transcript_hashes : Array[String] = []
  let durations : Array[Double] = []
  let resolved_sources : Array[@render.ReelSource] = []
  let mut total_bytes = 0L
  for source_index, source in recipe.sources {
    let path = recipe_source_path(parent, source.media)
    let transcript_path = recipe_source_path(parent, source.transcript)
    let transcript_bytes = local_file(transcript_path, 2097152)
    let parsed = @media.parse_subtitles(
      transcript_bytes,
      mime(source.transcript),
      7200000,
      1000,
    )
    let identity = file_identity(path)
    if from_record {
      guard saved_sources[source_index]
        is {
          "id": String(id),
          "media_sha256": String(media_hash),
          "transcript_sha256": String(caption_hash),
          ..
        } &&
        id == source.id &&
        media_hash == identity.1 &&
        caption_hash == digest(transcript_bytes) else {
        fail("edit record source identity mismatch: " + source.id)
      }
    }
    total_bytes += identity.0
    guard total_bytes <= 2147483648L else {
      fail("recipe source media exceeds 2 GiB total")
    }
    let probe = @render.probe_reel_source(path)
    guard probe
      is {
        "streams": Array(streams),
        "format": {
          "duration": String(duration),
          "format_name": String(format),
          ..
        },
        ..
      } else {
      fail("source requires known streams, format and duration")
    }
    guard format == "mov,mp4,m4a,3gp,3g2,mj2" ||
      format == "matroska,webm" ||
      format == "avi" else {
      fail("supported local source containers are MP4/MOV, MKV/WebM and AVI")
    }
    let source_ms = @string.parse_double(duration) * 1000.0
    guard source_ms > 0.0 && source_ms <= 7200000.0 else {
      fail("source duration must be positive and at most two hours")
    }
    guard streams
      .iter()
      .find_first(s => s is { "codec_type": String("video"), .. })
      is Some(video) else {
      fail("source must contain video")
    }
    guard video is { "width": Number(width), "height": Number(height), .. } &&
      width >= 2.0 &&
      height >= 2.0 &&
      width <= 8192.0 &&
      height <= 8192.0 else {
      fail("source video dimensions are unsupported")
    }
    if video is { "sample_aspect_ratio": String(sar), .. } {
      guard sar == "1:1" || sar == "N/A" else {
        fail("source video must use square pixels")
      }
    }
    guard !(video is { "disposition": { "attached_pic": Number(1), .. }, .. }) else {
      fail("attached cover art is not source video")
    }
    for stream in streams {
      if stream
        is { "codec_type": String(kind), "start_time": String(start), .. } &&
        (kind == "video" || kind == "audio") {
        let ms = @string.parse_double(start) * 1000.0
        guard ms >= -1.0 && ms <= 1.0 else {
          fail(
            "source streams must start at zero; offset streams require prior conforming",
          )
        }
      }
    }
    let has_audio = streams.any(s => s is { "codec_type": String("audio"), .. })
    inputs.push(path)
    transcripts.push(parsed.cues)
    audio.push(has_audio)
    hashes.push(identity)
    transcript_paths.push(transcript_path)
    transcript_hashes.push(digest(transcript_bytes))
    let video_ms = if video is { "duration": String(value), .. } {
      @string.parse_double(value) * 1000.0
    } else {
      source_ms
    }
    guard video_ms > 0.0 && video_ms <= 7200000.0 else {
      fail("video duration is unsupported")
    }
    durations.push(if video_ms < source_ms { video_ms } else { source_ms })
    resolved_sources.push({
      id: source.id,
      media: path,
      transcript: transcript_path,
    })
    identities.push({
      "id": source.id,
      "media": path,
      "media_bytes": identity.0.to_json(),
      "media_sha256": identity.1,
      "transcript": transcript_path,
      "transcript_sha256": digest(transcript_bytes),
      "parser_version": parsed.parser_version,
      "cue_digest": parsed.cue_digest,
      "has_audio": has_audio.to_json(),
      "probe": probe,
    })
  }
  let reel = @render.multi_source_reel(recipe, transcripts)
  guard reel.excerpts.all(e => {
    e.source_end_ms.to_double() <= durations[e.source_index]
  }) else {
    fail("selected transcript extends beyond source media")
  }
  let plan_digest = digest(@utf8.encode(reel.to_json().stringify()))
  let srt = @utf8.encode(reel.srt())
  @fs.write_file(output + ".srt", srt, create_mode=CreateNew)
  let receipt = @render.render_multi_source_reel(
    reel,
    inputs,
    audio,
    output + ".srt",
    output + ".mp4",
    plan_digest,
  )
  guard receipt.succeeded else {
    fail("render failed; partial outputs retained: " + receipt.stderr_tail)
  }
  let output_probe = @render.probe_reel_source(output + ".mp4")
  guard output_probe
    is {
      "streams": Array(streams),
      "format": { "duration": String(duration), .. },
      ..
    } else {
    fail("rendered output is unmeasurable")
  }
  let measured = @string.parse_double(duration) * 1000.0
  let expected = reel.duration_frames.to_double() * 1000.0 / 30.0
  guard measured >= expected - 34.0 &&
    measured <= expected + 100.0 &&
    streams.any(s => {
      s
      is {
        "codec_name": String("h264"),
        "width": Number(w),
        "height": Number(h),
        "nb_frames": String(frames),
        ..
      } &&
      w == recipe.canvas.width.to_double() &&
      h == recipe.canvas.height.to_double() &&
      frames == reel.duration_frames.to_string()
    }) &&
    streams.any(s => {
      s
      is {
        "codec_name": String("aac"),
        "sample_rate": String("48000"),
        "channels": Number(2),
        ..
      }
    }) &&
    streams.any(s => s is { "codec_name": String("mov_text"), .. }) else {
    fail(
      "rendered streams or duration do not match the plan; partial output retained",
    )
  }
  for i, input in inputs {
    guard file_identity(input) == hashes[i] &&
      digest(local_file(transcript_paths[i], 2097152)) == transcript_hashes[i] else {
      fail(
        "source changed during render; outputs retained without a success record",
      )
    }
  }
  guard local_file(recipe_path, input_limit) == recipe_bytes else {
    fail("recipe changed during render")
  }
  let normalized : @render.ReelRecipe = { ..recipe, sources: resolved_sources, }
  let output_identity = file_identity(output + ".mp4")
  let manifest : Json = {
    "contract": "mooncast.multi-source-reel-delivery.v1",
    "input_sha256": digest(recipe_bytes),
    "input_kind": if from_record {
      "edit-record"
    } else {
      "recipe"
    },
    "recipe_sha256": digest(@utf8.encode(normalized.to_json().stringify())),
    "recipe": normalized.to_json(),
    "sources": identities.to_json(),
    "reel": reel.to_json(),
    "plan_sha256": plan_digest,
    "render_receipt": receipt.to_json(),
    "output_probe": output_probe,
    "output_media_sha256": output_identity.1,
    "sidecar_sha256": digest(srt),
    "tool_versions": @render.reel_tool_versions(),
    "timing_policy": "30fps; each excerpt rounds up to whole frames; captions keep source offsets; held-video/silent tail",
    "audio_policy": "first audio stream, resampled to 48000 Hz stereo; missing streams and rounded tails are silent",
    "publication_authority": false,
  }
  let manifest_bytes = @utf8.encode(manifest.stringify(indent=2))
  guard manifest_bytes.length() <= 33554432 else {
    fail("edit record exceeds 32 MiB; partial outputs retained")
  }
  @fs.write_file(output + ".json", manifest_bytes, create_mode=CreateNew)
  println(
    "Created " +
    output +
    ".mp4, .srt and .json (" +
    reel.duration_frames.to_string() +
    " frames, " +
    reel.excerpts.length().to_string() +
    " excerpts)",
  )
}
