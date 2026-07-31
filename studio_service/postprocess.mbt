///|
struct PostprocessTaskRequest {
  task : @postprocess.PostprocessTask
} derive(FromJson)

///|
async fn StudioService::record_postprocess_task(
  self : StudioService,
  project_id : String,
  input : PostprocessTaskRequest,
) -> @postprocess.PostprocessTask {
  let canonical = self.get_project(project_id)
  guard gate_recorded(canonical.snapshot, "G3") else {
    raise Conflict(
      code="postprocess_g3_required",
      message="postprocess requires the approved rendered animatic and production route",
    )
  }
  let base = {
    ..input.task,
    project_id,
    project_revision: canonical.snapshot.revision,
    reference: { ..input.task.reference, digest: "" },
    provider_execution_authority: false,
    publication_authority: false,
  }
  let exact = {
    ..base,
    reference: { ..base.reference, digest: @postprocess.task_digest(base) },
  }
  self.postprocess.record_task(exact, canonical.snapshot.graph)
}

///|
async fn StudioService::bind_postprocess_output(
  self : StudioService,
  project_id : String,
  input : @postprocess_app.PostprocessBindRequest,
) -> @postprocess.PostprocessImportBinding {
  let canonical = self.get_project(project_id)
  let outputs = self.postprocess.workspace(project_id).outputs
  let matches = outputs.filter(output => {
    output.reference.asset_id == input.output_asset_id &&
    output.reference.version == input.output_asset_version
  })
  guard matches.length() == 1 else {
    raise NotFound(entity="postprocess_output", id=input.output_asset_id)
  }
  let output = matches[0]
  let exact = match input.destination_kind {
    "shot" => {
      guard @project.flattened_shots(canonical.snapshot.graph).any(shot => {
        shot.shot_id == input.destination_id
      }) else {
        raise Conflict(
          code="postprocess_shot_missing",
          message="shot destination is not current",
        )
      }
      input
    }
    "delivery" => {
      guard self.delivery_application
        .list(project_id)
        .any(build => build.build_id == input.destination_id) else {
        raise Conflict(
          code="postprocess_delivery_missing",
          message="delivery destination was not found",
        )
      }
      input
    }
    "editor" => {
      guard self.editor_repository.load_snapshot(input.destination_id)
        is Some(_) &&
        self.execution_application.artifact_metadata(output.reference.digest)
        is Some(metadata) &&
        self.execution_application.artifact_bytes(output.reference.digest)
        is Some(bytes) else {
        raise Conflict(
          code="postprocess_editor_import_failed",
          message="editor or provider media is unavailable",
        )
      }
      let media = self.editor_media.ingest(
        bytes,
        metadata.media_type,
        None,
        "original",
        None,
        output.source_assets.map(asset => asset.digest),
        [output.provenance_digest],
        output.rights_refs,
        input.bound_at,
      )
      { ..input, editor_media_digest: Some(media.digest) }
    }
    _ => input
  }
  self.postprocess.bind(project_id, exact)
}

///|
async fn StudioService::dispatch_postprocess_http(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response? {
  let segments = path_segments(request.path)
  match (request.request_method, segments) {
    (Get, ["api", "v2", "projects", project_id, "postprocess-jobs"]) =>
      Some(json_value_response(200, self.postprocess.workspace(project_id)))
    (Post, ["api", "v2", "projects", project_id, "postprocess-jobs", "tasks"]) => {
      let input : PostprocessTaskRequest = decode_body(request)
      Some(
        json_value_response(
          201,
          self.record_postprocess_task(project_id, input),
        ),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "postprocess-jobs", "run"]) => {
      let input : @postprocess_app.PostprocessRunRequest = decode_body(request)
      Some(json_value_response(201, self.postprocess.run(project_id, input)))
    }
    (Post, ["api", "v2", "projects", project_id, "postprocess-jobs", "imports"]) => {
      let input : @postprocess_app.PostprocessBindRequest = decode_body(request)
      Some(
        json_value_response(
          201,
          self.bind_postprocess_output(project_id, input),
        ),
      )
    }
    _ => None
  }
}

///|
pub fn StudioService::register_postprocess_routes(self : StudioService) -> Unit {
  self.register_route_extension(
    RouteExtension::new("/api/v2/projects", async fn(request) {
      self.dispatch_postprocess_http(request)
    }),
  )
}
