///|
struct ProbeStream {
  codec_type : String
  codec_name : String
  width : Int?
  height : Int?
  sample_rate : String?
  channels : Int?
} derive(FromJson)

///|
struct ProbeFormat {
  duration : String
} derive(FromJson)

///|
struct ProbeDocument {
  streams : Array[ProbeStream]
  format : ProbeFormat
} derive(FromJson)

///|
pub async fn probe(
  ffprobe : String,
  source_path : String,
  digest : String,
  source_size : Int,
  mime : String,
  analysis_id : String,
  analysis_digest : String,
) -> MediaAnalysis {
  let result = @process.run_capture({
    executable: ffprobe,
    arguments: [
      "-v", "error", "-show_streams", "-show_format", "-of", "json", source_path,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 1048576,
  })
  guard result.exit_code == Some(0) &&
    !result.timed_out &&
    !result.output_truncated else {
    fail("ffprobe analysis failed")
  }
  let document : ProbeDocument = @json.from_json(
    @json.parse(@utf8.decode(result.stdout)),
  )
  let mut width = 0
  let mut height = 0
  let mut video_codec = ""
  let mut audio_codec = ""
  let mut sample_rate = 0
  let mut channels = 0
  for stream in document.streams {
    if stream.codec_type == "video" {
      video_codec = stream.codec_name
      if stream.width is Some(value) {
        width = value
      }
      if stream.height is Some(value) {
        height = value
      }
    }
    if stream.codec_type == "audio" {
      audio_codec = stream.codec_name
      if stream.sample_rate is Some(value) {
        sample_rate = @string.parse_int(value) catch { _ => 0 }
      }
      if stream.channels is Some(value) {
        channels = value
      }
    }
  }
  {
    contract: "mooncast.editor-media-analysis.v1",
    analysis_version: "ffprobe-json-v1",
    analysis_id,
    source_digest: digest,
    source_size,
    source_mime: mime,
    state: "available",
    duration_seconds: Some(
      @string.parse_double(document.format.duration) catch {
        _ => 0.0
      },
    ),
    video: {
      state: if video_codec == "" {
        "unavailable"
      } else {
        "available"
      },
      width: if width == 0 {
        None
      } else {
        Some(width)
      },
      height: if height == 0 {
        None
      } else {
        Some(height)
      },
      codec: if video_codec == "" {
        None
      } else {
        Some(video_codec)
      },
    },
    audio: {
      state: if audio_codec == "" {
        "unavailable"
      } else {
        "available"
      },
      channels: if channels == 0 {
        None
      } else {
        Some(channels)
      },
      sample_rate: if sample_rate == 0 {
        None
      } else {
        Some(sample_rate)
      },
      codec: if audio_codec == "" {
        None
      } else {
        Some(audio_codec)
      },
    },
    thumbnail: {
      state: "unavailable",
      digest: None,
      mime: None,
      width: None,
      height: None,
    },
    waveform: { state: "unavailable", peak_count: 0, peaks: [], digest: None },
    analysis_digest: Some(analysis_digest),
    source_url: None,
    thumbnail_url: None,
    publication_authority: false,
    provider_authority: false,
  }
}
