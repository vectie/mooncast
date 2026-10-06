///|
struct VerifiedDeliveryCaptions {
  bytes : Bytes
  metadata : Json
}

///|
/// Select only the sidecar that was verified with the exact promoted export.
/// No path, text, or language supplied by the delivery caller becomes evidence.
async fn StudioService::verified_delivery_captions(
  self : StudioService,
  project_id : String,
) -> VerifiedDeliveryCaptions {
  let canonical = self.get_project(project_id)
  guard canonical.snapshot.master is Some(master) &&
    self.latest_editor_promotion(project_id) is Some(promotion) &&
    promotion.project_id == project_id &&
    normalized_digest(promotion.digest) ==
    normalized_digest(master.video_digest) else {
    fail(
      "Captions missing: export and promote the current master with verified subtitles in Cut Editor.",
    )
  }
  let job = self.get_editor_job(project_id, promotion.job_id)
  guard job.job.project_id == project_id &&
    job.job.kind == "export" &&
    job.job.state == "succeeded" &&
    job.export_receipt is Some(receipt) &&
    receipt.digest == promotion.digest &&
    receipt.plan_digest == promotion.plan_digest &&
    job.render_plan.project_id == project_id &&
    job.render_plan.plan_digest == receipt.plan_digest else {
    fail("Selected captions do not belong to the exact promoted export.")
  }
  ignore(self.resolve_editor_job_media(project_id, promotion.job_id))
  guard self.editor_render_files.get_blob(
      editor_subtitle_key(project_id, promotion.job_id),
    )
    is Some(blob) &&
    self.editor_render_files.get_json(
      editor_provenance_key(project_id, promotion.job_id),
    )
    is Some(provenance) else {
    fail(
      "Captions missing: restore the verified export sidecar or create and promote a new export in Cut Editor.",
    )
  }
  let sidecar = @editor_render.subtitle_sidecar(job.render_plan)
  let digest = "sha256:" + blob.sha256
  guard !blob.bytes.is_empty() &&
    blob.bytes == @utf8.encode(sidecar.content) &&
    sidecar.digest == digest &&
    json_member(provenance, "project_id") == Some(project_id.to_json()) &&
    json_member(provenance, "job_id") == Some(promotion.job_id.to_json()) &&
    json_member(provenance, "output_digest") == Some(receipt.digest.to_json()) &&
    json_member(provenance, "plan_digest") ==
    Some(receipt.plan_digest.to_json()) &&
    json_member(provenance, "subtitle_digest") == Some(digest.to_json()) else {
    fail(
      "Selected captions changed or lost their export provenance. Restore the verified sidecar or create a new export.",
    )
  }
  let parsed = @editor_media.parse_subtitles(
    blob.bytes,
    "application/x-subrip",
    job.render_plan.range.duration_ticks,
    job.render_plan.timebase.ticks_per_second,
  )
  let bindings : Array[Json] = []
  for track in job.render_plan.tracks {
    for clip in track.clips {
      if clip.local_media is Some(binding) && binding.role == "subtitle" {
        guard binding.project_id == project_id &&
          clip.identity.project_id == project_id &&
          canonical.snapshot.graph.episodes.any(episode => {
            episode.episode_id == clip.identity.episode_id
          }) else {
          fail("Caption asset belongs to another project or episode.")
        }
        bindings.push(clip.to_json())
      }
    }
  }
  guard !bindings.is_empty() else {
    fail("Verified caption source bindings are missing.")
  }
  {
    bytes: blob.bytes,
    metadata: {
      "contract": "mooncast.delivery-caption-selection.v1",
      "project_id": project_id,
      "master_sha256": normalized_digest(master.video_digest),
      "master_version": master.reference.version,
      "export_job_id": promotion.job_id,
      "editor_revision": job.render_plan.project_revision,
      "timeline_revision": job.render_plan.timeline_revision,
      "plan_digest": receipt.plan_digest,
      "sha256": digest,
      "format": "srt",
      "language": "und",
      "language_provenance": "No language tag was recorded in the verified subtitle asset; content is preserved without inference.",
      "cue_count": parsed.cues.length(),
      "cue_digest": parsed.cue_digest,
      "parser_version": parsed.parser_version,
      "timebase": job.render_plan.timebase.to_json(),
      "range": job.render_plan.range.to_json(),
      "source_clips": bindings.to_json(),
      "download_url": "/api/v2/projects/" +
      project_id +
      "/delivery-captions/" +
      blob.sha256 +
      "/download",
      "publication_authority": false,
    },
  }
}

///|
async fn StudioService::delivery_captions_page(
  self : StudioService,
  project_id : String,
  cut? : @execution.DeliveryOutputSpec,
) -> @host_http.Response {
  ignore(self.get_project(project_id))
  let escape = workspace_html_escape
  let body = try {
    match cut {
      Some(output) => self.verified_delivery_cut_captions(project_id, output)
      None => self.verified_delivery_captions(project_id)
    }
  } catch {
    error =>
      "<h1>Verified captions need attention</h1><p>" +
      escape(error.to_string()) +
      "</p><p>Restore the verified SRT, choose a supported contiguous captioned range, or open Cut Editor to import a rights-cleared subtitle asset, export, and promote a new master. Required captions cannot be omitted.</p>"
  } noraise {
    selected =>
      (match cut {
        Some(output) =>
          "<h1>Selected captions for this cut</h1><p>Cut: " +
          escape(output.output_id) +
          "; source: master; range " +
          escape(output.in_seconds.unwrap().to_string()) +
          "–" +
          escape(output.out_seconds.unwrap().to_string()) +
          " seconds. Caption source: the exact promoted master SRT. Crossing cues are clipped to this half-open range and rebased to zero. Reordered, retimed or chained cuts require a new Cut Editor export.</p>"
        None => "<h1>Selected captions for this master</h1>"
      }) +
      "<p>Automatically selected from the exact promoted export. These SRT bytes and their timing are frozen when you create the delivery build.</p><p>Language: und (not recorded in the source; no language inferred).</p><p><a href=\"" +
      escape(ledger_text(selected.metadata, "download_url")) +
      "\" download=\"subtitles.srt\">Download selected SRT</a></p><h2>Caption preview</h2><pre>" +
      escape(@utf8.decode(selected.bytes)) +
      "</pre>" +
      ledger_detail(
        "Caption version, timing and source provenance",
        selected.metadata,
      )
  }
  {
    status: 200,
    reason: "OK",
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    },
    body: @utf8.encode(
      "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>Delivery captions</title><style>body{font:16px system-ui;max-width:72rem;margin:2rem auto;padding:1rem;background:#101219;color:#f2f4fc}a{color:#a8d7ff}pre{white-space:pre-wrap;overflow-wrap:anywhere;padding:1rem;background:#202430}summary{cursor:pointer}</style><main>" +
      body +
      "<p><a href=\"/editor\">Open Cut Editor</a> and select project <strong>" +
      escape(project_id) +
      "</strong> to correct missing or changed captions, then return to Delivery.</p></main></html>",
    ),
  }
}

///|
fn delivery_caption_cut(
  start : String,
  finish : String,
) -> @execution.DeliveryOutputSpec raise {
  let start_ms = @string.parse_int(start)
  let end_ms = @string.parse_int(finish)
  let output = delivery_output(
    "selected-cut", "channel-cut", 1920, 1080, "sidecar", "caption-preview",
  )
  {
    ..output,
    source_output_id: Some("master"),
    in_seconds: Some(start_ms.to_double() / 1000.0),
    out_seconds: Some(end_ms.to_double() / 1000.0),
  }
}

///|
async fn StudioService::verified_delivery_cut_captions(
  self : StudioService,
  project_id : String,
  cut : @execution.DeliveryOutputSpec,
) -> VerifiedDeliveryCaptions {
  let selected = self.verified_delivery_captions(project_id)
  let master = self.get_project(project_id).snapshot.master.unwrap()
  let derived = @execution_app.delivery_output_captions(
    selected.bytes,
    master.duration_seconds.to_double(),
    cut,
  )
  let start_ms = (cut.in_seconds.unwrap() * 1000.0).round().to_int()
  let end_ms = (cut.out_seconds.unwrap() * 1000.0).round().to_int()
  {
    bytes: @utf8.encode(derived.content),
    metadata: {
      "contract": "mooncast.delivery-cut-caption-selection.v1",
      "sha256": derived.digest,
      "source_selection": selected.metadata,
      "mapping": derived.mapping,
      "download_url": "/api/v2/projects/" +
      project_id +
      "/delivery-captions/cut/" +
      start_ms.to_string() +
      "/" +
      end_ms.to_string() +
      "/" +
      derived.digest[7:].to_owned() +
      "/download",
      "publication_authority": false,
    },
  }
}
