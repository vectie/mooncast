///|
suberror AnnotationTestError {
  AnnotationTestError
}

///|
fn client_step(model : Model, message : Msg) -> Model {
  update(_ => @rabbita.none, message, model).1
}

///|
fn client_url(token : String) -> @url.Url {
  {
    protocol: @url.Http,
    host: "fixture.invalid",
    port: None,
    path: "/apps/mooncast/client/" + token,
    query: None,
    fragment: None,
  }
}

///|
fn client_fixture(id : String, build : String) -> ClientProjection {
  {
    contract: "fixture",
    brand: { name: "Fixture", accent: "blue", },
    portal: {
      portal_id: id,
      expires_at: "fixture",
      scopes: ["annotate"],
      status: Some("active"),
    },
    project: {
      project_id: "project-" + id,
      title: id,
      objective: "Review",
      target_duration_seconds: 30.0,
      episodes: [],
    },
    binding: {
      master_sha256: "master-" + build,
      delivery_digest: "delivery-" + build,
      build_id: build,
      build_digest: "digest-" + build,
    },
    review_master_url: "review.mp4",
    annotations: [],
    decisions: [],
    revision_policy: { maximum: 3, used: 0, remaining: 3, },
    delivery: {
      accepted: false,
      download_url: None,
      archive_name: None,
      artifacts: [],
    },
    provider_data_included: false,
    publication_authority: false,
  }
}

///|
fn annotation_fixture(id : String, build : String) -> ClientAnnotation {
  {
    contract: "fixture",
    annotation_id: "annotation-A",
    portal_id: id,
    master_sha256: "master-" + build,
    build_digest: "digest-" + build,
    timecode_seconds: 1.0,
    body: "note A",
    author: "Reviewer",
    created_at: "fixture",
    digest: "annotation-digest",
  }
}

///|
fn active_client(id : String, build : String) -> Model {
  let model = client_step(initial_model(Some(client_url(id))), Reload)
  client_step(
    model,
    ProjectionLoaded(
      model.portal_generation,
      model.projection_generation,
      Ok(client_fixture(id, build)),
    ),
  )
}

///|
fn annotation_ready() -> Model {
  let model = active_client("A", "build-A")
  let model = client_step(model, AnnotationAuthorChanged("Reviewer"))
  let model = client_step(model, AnnotationTimecodeChanged("1.000"))
  client_step(model, AnnotationBodyChanged("note A"))
}

///|
test "annotation completion preserves newer text and appends the receipt once" {
  let submitted = client_step(annotation_ready(), SubmitAnnotation)
  let operation = submitted.pending_annotation.unwrap()
  let version = submitted.annotation_version
  let edited = client_step(submitted, AnnotationBodyChanged("note B"))
  let completed = client_step(
    edited,
    AnnotationSaved(operation, version, Ok(annotation_fixture("A", "build-A"))),
  )
  assert_eq(completed.annotation.body, "note B")
  assert_eq(completed.projection.unwrap().annotations.length(), 1)
  assert_false(completed.busy)
  let duplicate = client_step(
    completed,
    AnnotationSaved(operation, version, Ok(annotation_fixture("A", "build-A"))),
  )
  assert_eq(duplicate.projection.unwrap().annotations.length(), 1)
  assert_eq(duplicate.annotation.body, "note B")
}

///|
test "unchanged submitted annotation clears only its body" {
  let submitted = client_step(annotation_ready(), SubmitAnnotation)
  let completed = client_step(
    submitted,
    AnnotationSaved(
      submitted.pending_annotation.unwrap(),
      submitted.annotation_version,
      Ok(annotation_fixture("A", "build-A")),
    ),
  )
  assert_eq(completed.annotation.body, "")
  assert_eq(completed.annotation.author, "Reviewer")
  assert_eq(completed.annotation.timecode, "1.000")
  assert_true(completed.pending_annotation is None)
}

///|
test "annotation failure preserves current edits and permits an explicit resubmit" {
  let submitted = client_step(annotation_ready(), SubmitAnnotation)
  let edited = client_step(submitted, AnnotationBodyChanged("note B"))
  let failed = client_step(
    edited,
    AnnotationSaved(
      submitted.pending_annotation.unwrap(),
      submitted.annotation_version,
      Err(AnnotationTestError),
    ),
  )
  assert_eq(failed.annotation.body, "note B")
  assert_eq(failed.api_error.unwrap().code, "annotation_failed")
  assert_false(failed.busy)
  let resubmit = client_step(failed, SubmitAnnotation)
  assert_eq(resubmit.operation_sequence, submitted.operation_sequence + 1)
  let stale = client_step(
    resubmit,
    AnnotationSaved(
      submitted.pending_annotation.unwrap(),
      submitted.annotation_version,
      Ok(annotation_fixture("A", "build-A")),
    ),
  )
  assert_true(stale.pending_annotation == resubmit.pending_annotation)
  assert_true(stale.busy)
  assert_eq(stale.projection.unwrap().annotations.length(), 0)
}

///|
test "annotation author timecode and edit-away-and-back count as newer draft edits" {
  let submitted = client_step(annotation_ready(), SubmitAnnotation)
  let operation = submitted.pending_annotation.unwrap()
  let version = submitted.annotation_version
  for
    message in [
      AnnotationAuthorChanged("Other reviewer"),
      AnnotationTimecodeChanged("2.000"),
    ] {
    let edited = client_step(submitted, message)
    let completed = client_step(
      edited,
      AnnotationSaved(
        operation,
        version,
        Ok(annotation_fixture("A", "build-A")),
      ),
    )
    assert_eq(completed.annotation.body, "note A")
  }
  let edited = client_step(
    client_step(submitted, AnnotationBodyChanged("note B")),
    AnnotationBodyChanged("note A"),
  )
  let completed = client_step(
    edited,
    AnnotationSaved(operation, version, Ok(annotation_fixture("A", "build-A"))),
  )
  assert_eq(completed.annotation.body, "note A")
}

///|
test "old portal annotation and projection callbacks cannot touch a newer portal or ABA visit" {
  let submitted = client_step(annotation_ready(), SubmitAnnotation)
  let operation = submitted.pending_annotation.unwrap()
  let opening_b = client_step(submitted, UrlChanged(client_url("B")))
  let active_b = client_step(
    opening_b,
    ProjectionLoaded(
      opening_b.portal_generation,
      opening_b.projection_generation,
      Ok(client_fixture("B", "build-B")),
    ),
  )
  let draft_b = client_step(active_b, AnnotationBodyChanged("B draft"))
  let results : Array[Result[ClientAnnotation, Error]] = [
    Ok(annotation_fixture("A", "build-A")),
    Err(AnnotationTestError),
  ]
  for result in results {
    let late = client_step(
      draft_b,
      AnnotationSaved(operation, submitted.annotation_version, result),
    )
    assert_eq(late.annotation.body, "B draft")
    assert_eq(late.projection.unwrap().project.project_id, "project-B")
    assert_eq(late.projection.unwrap().annotations.length(), 0)
    assert_true(late.api_error is None)
  }
  let opening_a = client_step(draft_b, UrlChanged(client_url("A")))
  let restored = client_step(
    opening_a,
    ProjectionLoaded(
      opening_a.portal_generation,
      opening_a.projection_generation,
      Ok(client_fixture("A", "build-A")),
    ),
  )
  assert_eq(restored.annotation.body, "note A")
  let late = client_step(
    restored,
    AnnotationSaved(
      operation,
      submitted.annotation_version,
      Ok(annotation_fixture("A", "build-A")),
    ),
  )
  assert_eq(late.annotation.body, "note A")
  assert_eq(late.projection.unwrap().annotations.length(), 0)
  let late_read = client_step(
    late,
    ProjectionLoaded(
      opening_b.portal_generation,
      opening_b.projection_generation,
      Ok(client_fixture("B", "build-B")),
    ),
  )
  assert_eq(late_read.projection.unwrap().portal.portal_id, "A")
}

///|
test "exact artifact changes retain separate annotation drafts" {
  let original = annotation_ready()
  let loading = client_step(original, Reload)
  let next = client_step(
    loading,
    ProjectionLoaded(
      loading.portal_generation,
      loading.projection_generation,
      Ok(client_fixture("A", "build-B")),
    ),
  )
  assert_eq(next.annotation.body, "")
  let next = client_step(next, AnnotationBodyChanged("build B note"))
  let loading = client_step(next, Reload)
  let restored = client_step(
    loading,
    ProjectionLoaded(
      loading.portal_generation,
      loading.projection_generation,
      Ok(client_fixture("A", "build-A")),
    ),
  )
  assert_eq(restored.annotation.body, "note A")
  let loading = client_step(restored, Reload)
  let failed = client_step(
    loading,
    ProjectionLoaded(
      loading.portal_generation,
      loading.projection_generation,
      Err(AnnotationTestError),
    ),
  )
  assert_eq(failed.annotation.body, "note A")
  assert_eq(failed.projection.unwrap().binding.build_id, "build-A")
}

///|
test "mismatched annotation receipt cannot clear text or append to this artifact" {
  let submitted = client_step(annotation_ready(), SubmitAnnotation)
  let completed = client_step(
    submitted,
    AnnotationSaved(
      submitted.pending_annotation.unwrap(),
      submitted.annotation_version,
      Ok(annotation_fixture("A", "other-build")),
    ),
  )
  assert_eq(completed.annotation.body, "note A")
  assert_eq(completed.projection.unwrap().annotations.length(), 0)
  assert_eq(completed.api_error.unwrap().code, "annotation_context_mismatch")
  assert_false(completed.busy)
}

///|
test "pending annotation coalesces duplicate submission and reload" {
  let submitted = client_step(annotation_ready(), SubmitAnnotation)
  for
    message in [
      SubmitAnnotation,
      Reload,
      UrlChanged(client_url("A")),
      SubmitDecision,
    ] {
    let next = client_step(submitted, message)
    assert_true(next.pending_annotation == submitted.pending_annotation)
    assert_eq(next.operation_sequence, submitted.operation_sequence)
    assert_eq(next.projection_generation, submitted.projection_generation)
    assert_true(next.busy)
  }
}

///|
test "stale same-portal projection results cannot replace the latest read" {
  let first = client_step(annotation_ready(), Reload)
  let second = client_step(first, Reload)
  let newer = client_step(
    second,
    ProjectionLoaded(
      second.portal_generation,
      second.projection_generation,
      Ok(client_fixture("A", "build-B")),
    ),
  )
  let older = client_step(
    newer,
    ProjectionLoaded(
      first.portal_generation,
      first.projection_generation,
      Ok(client_fixture("A", "build-A")),
    ),
  )
  assert_eq(older.projection.unwrap().binding.build_id, "build-B")
}

///|
test "late decision cannot close a new portal or clear its annotation draft" {
  let ready = client_step(
    client_step(annotation_ready(), DecisionActorChanged("Reviewer")),
    ToggleDecisionConfirmation,
  )
  let pending = client_step(ready, SubmitDecision)
  let operation = pending.pending_decision.unwrap()
  let opening = client_step(pending, UrlChanged(client_url("B")))
  let next = client_step(
    opening,
    ProjectionLoaded(
      opening.portal_generation,
      opening.projection_generation,
      Ok(client_fixture("B", "build-B")),
    ),
  )
  let next = client_step(next, AnnotationAuthorChanged("Reviewer B"))
  let next = client_step(next, AnnotationBodyChanged("B note"))
  let next = client_step(next, SubmitAnnotation)
  let receipt : ClientDecisionReceipt = {
    contract: "fixture",
    portal_id: "A",
    decision: "reject",
    master_sha256: "master-build-A",
    build_digest: "digest-build-A",
    governance_receipt_digest: "fixture",
    project_revision: 1,
    decided_at: "fixture",
    digest: "fixture",
  }
  let results : Array[Result[ClientDecisionReceipt, Error]] = [
    Ok(receipt),
    Err(AnnotationTestError),
  ]
  for result in results {
    let late = client_step(next, DecisionSaved(operation, "reject", result))
    assert_true(late.availability == Active)
    assert_eq(late.annotation.body, "B note")
    assert_true(late.pending_annotation == next.pending_annotation)
    assert_true(late.busy)
    assert_true(late.api_error is None)
  }
}

///|
struct AnnotationTestScheduler {
  hooks : @cmd.Hooks
}

///|
impl @cmd.Scheduler for AnnotationTestScheduler with fn run_effect(
  self,
  _kind,
  effect,
) {
  effect(self)
}

///|
impl @cmd.Scheduler for AnnotationTestScheduler with fn queue_message(
  _self,
  _id,
  send,
) {
  send()
}

///|
impl @cmd.Scheduler for AnnotationTestScheduler with fn drain_message(_self) {
  ()
}

///|
impl @cmd.Scheduler for AnnotationTestScheduler with fn hooks(self) {
  self.hooks
}

///|
extern "js" fn install_annotation_http_fixture() -> Unit =
  #| () => {
  #|   globalThis.__castAnnotationFixture = { oldFetch: globalThis.fetch, requests: [], callbacks: [] };
  #|   globalThis.fetch = (url, options) => {
  #|     const state = globalThis.__castAnnotationFixture;
  #|     state.requests.push({url, method: options.method, body: options.body ? JSON.parse(options.body) : null});
  #|     const pending = { success: null, failure: null };
  #|     state.callbacks.push(pending);
  #|     const chain = { then(fn) { pending.success = fn; return chain; }, catch(fn) { pending.failure = fn; return chain; } };
  #|     return chain;
  #|   };
  #| }

///|
extern "js" fn annotation_fixture_reply(index : Int, body : String) -> Unit =
  #| (index, body) => { globalThis.__castAnnotationFixture.callbacks[index].success({text() { return {then(fn) { fn(body); }}; }}); }

///|
extern "js" fn annotation_fixture_requests() -> String = "() => JSON.stringify(globalThis.__castAnnotationFixture.requests)"

///|
extern "js" fn restore_annotation_http_fixture() -> Unit = "() => { globalThis.fetch = globalThis.__castAnnotationFixture.oldFetch; delete globalThis.__castAnnotationFixture; }"

///|
test "actual annotation HTTP command submits A once and delayed completion preserves B" {
  install_annotation_http_fixture()
  defer restore_annotation_http_fixture()
  let scheduler = AnnotationTestScheduler::{
    hooks: { url_request: None, url_changed: None, },
  }
  let cell = Ref(annotation_ready())
  fn dispatch(message : Msg) -> @rabbita.Cmd {
    let (command, next) = update(dispatch, message, cell.val)
    cell.val = next
    @cmd.Scheduler::add(scheduler, command)
    @rabbita.none
  }
  ignore(dispatch(SubmitAnnotation))
  ignore(dispatch(SubmitAnnotation))
  ignore(dispatch(AnnotationBodyChanged("note B")))
  let requests = @json.parse(annotation_fixture_requests())
  assert_eq(requests, [
    {
      "url": "/api/client/A/annotations",
      "method": "POST",
      "body": {
        "expected_master_sha256": "master-build-A",
        "expected_build_digest": "digest-build-A",
        "timecode_seconds": 1,
        "author": "Reviewer",
        "body": "note A",
      },
    },
  ])
  let receipt : Json = {
    "contract": "fixture",
    "annotation_id": "annotation-A",
    "portal_id": "A",
    "master_sha256": "master-build-A",
    "build_digest": "digest-build-A",
    "timecode_seconds": 1,
    "body": "note A",
    "author": "Reviewer",
    "created_at": "fixture",
    "digest": "annotation-digest",
  }
  annotation_fixture_reply(0, receipt.stringify())
  annotation_fixture_reply(0, receipt.stringify())
  assert_eq(cell.val.annotation.body, "note B")
  assert_eq(cell.val.projection.unwrap().annotations.length(), 1)
  assert_false(cell.val.busy)
}

///|
test "pending and completed annotation views retain editable newer draft and outcome" {
  let pending = client_step(annotation_ready(), SubmitAnnotation)
  let edited = client_step(
    pending,
    AnnotationBodyChanged("Visible newer draft"),
  )
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(view(_ => @rabbita.none, edited)),
  )
  assert_true(html.contains("Visible newer draft"))
  assert_true(html.contains("Recording an immutable timecode annotation"))
  let completed = client_step(
    edited,
    AnnotationSaved(
      pending.pending_annotation.unwrap(),
      pending.annotation_version,
      Ok(annotation_fixture("A", "build-A")),
    ),
  )
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(view(_ => @rabbita.none, completed)),
  )
  assert_true(html.contains("Visible newer draft"))
  assert_true(html.contains("Annotation recorded against the exact master"))
  assert_true(html.contains("note A"))
}
