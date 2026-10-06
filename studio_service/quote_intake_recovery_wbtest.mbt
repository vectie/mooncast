///|
suberror IntakeFixtureInterruption {
  IntakeFixtureInterruption(String)
} derive(Debug)

///|
async fn intake_fixture_request(
  service : StudioService,
  quote : QuoteProjection,
) -> QuoteConversionInput {
  {
    expected_version: quote.version,
    expected_digest: quote.digest,
    expected_capacity_digest: service.commerce_application
    .capacity_board(quote_id=quote.quote_id)
    .unwrap().digest,
    human_confirmed: true,
    actor: "fixture-producer",
    actor_role: "producer",
  }
}

///|
async fn interrupt_intake(
  service : StudioService,
  quote : QuoteProjection,
  request : QuoteConversionInput,
  at : String,
) -> Unit {
  try
    service.convert_quote_intake(quote.quote_id, request, async fn(step) {
      if step == at {
        save_value(service.store, "fixture-interruption.json", step)
        raise IntakeFixtureInterruption(step)
      }
    })
  catch {
    IntakeFixtureInterruption(step) => assert_eq(step, at)
    error => raise error
  } noraise {
    _ => fail("Expected persisted interruption at " + at)
  }
}

///|
async test "quote intake resumes every persisted effect and checkpoint after restart" {
  let boundaries = ["plan", "complete"]
  for
    step in [
      "conversion", "project", "metadata", "qualification", "brief", "rights-ledger",
      "ip-bible", "script", "claims-ledger", "storyboard", "animatic", "projection",
    ] {
    boundaries.push(step + ":effect")
    boundaries.push(step + ":checkpoint")
  }
  for index, boundary in boundaries {
    let root = "/tmp/mooncast-intake-boundary-" +
      @async.now().to_string() +
      "-" +
      index.to_string()
    let service = StudioService::new(root)
    let quote = ledger_quote_fixture(
      service, "interrupted-intake", "SYNTHETIC interrupted intake",
    )
    let request = intake_fixture_request(service, quote)
    interrupt_intake(service, quote, request, boundary)
    let marker : String = load_value(service.store, "fixture-interruption.json").unwrap()
    assert_eq(marker, boundary)
    let restarted = StudioService::new(root)
    let result = restarted.convert_commercial_quote(quote.quote_id, request)
    assert_eq(result.conversion.initialization_status, Some("completed"))
    let project = restarted.get_project(quote.project.project_id)
    assert_eq(project.snapshot.creative_artifacts.length(), 7)
    assert_eq(project.command_receipts.length(), 8)
    assert_true(project.command_receipts.all(item => item.ok))
    let plan : QuoteIntakePlan = load_value(
      restarted.store,
      quote_intake_key(project.project_id),
    ).unwrap()
    assert_true(plan.complete)
    assert_eq(project.snapshot.creative_artifacts, plan.drafts)
    assert_eq(project.snapshot.qualification, Some(plan.qualification))
    assert_eq(
      restarted.production_repository.get(project.project_id),
      Some(project.snapshot),
    )
    let commerce = restarted.commerce_application.load()
    assert_eq(commerce.conversions.length(), 1)
    assert_eq(commerce.reservations.length(), 1)
    assert_eq(commerce.conversions[0], plan.conversion)
    ignore(restarted.convert_commercial_quote(quote.quote_id, request))
    assert_eq(restarted.get_project(project.project_id), project)
    assert_eq(restarted.commerce_application.load(), commerce)
  }
}

///|
async test "quote intake preserves partial edits and retains original seed dependencies" {
  let root = "/tmp/mooncast-intake-edits-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "edited-intake", "SYNTHETIC editable intake",
  )
  let request = intake_fixture_request(service, quote)
  interrupt_intake(service, quote, request, "brief:effect")
  let before = service.get_project(quote.project.project_id)
  let brief = before.snapshot.creative_artifacts[0]
  let revision = {
    ..brief,
    reference: {
      ..brief.reference,
      version: 2,
      digest: "sha256:human-edited-brief",
    },
    content: "Human revised brief, retain exactly",
  }
  let edited = service.record_creative_artifact(before.project_id, {
    expected_revision: before.snapshot.revision,
    command_id: "human-edit",
    recorded_at: "human-edit-time",
    evidence_digest: revision.reference.digest,
    artifact: revision,
  })
  assert_true(edited.result.ok)
  let metadata : ProjectExperienceMetadata = {
    objective: "Human edit",
    audience: "New audience",
    channels: ["internal"],
    rights_owner: "Human editor",
    rights_confirmed: false,
  }
  service.save_project_experience(before.project_id, metadata)
  let graph_edited = {
    ..edited.project,
    snapshot: {
      ..edited.project.snapshot,
      graph: { ..edited.project.snapshot.graph, title: "Edited project title", },
    },
  }
  save_value(service.store, project_key(before.project_id), graph_edited)
  let restarted = StudioService::new(root)
  ignore(restarted.convert_commercial_quote(quote.quote_id, request))
  let after = restarted.get_project(before.project_id)
  assert_eq(after.snapshot.graph.title, "Edited project title")
  assert_eq(after.snapshot.creative_artifacts.length(), 8)
  assert_eq(
    @creative.current_artifact(
      after.snapshot.creative_artifacts,
      @creative.Brief,
    ),
    Some(revision),
  )
  assert_eq(after.snapshot.creative_artifacts[2].dependency_digests, [
    brief.reference.digest,
  ])
  let actual : ProjectExperienceMetadata = load_value(
    restarted.store,
    project_experience_key(before.project_id),
  ).unwrap()
  assert_eq(actual.to_json(), metadata.to_json())
  assert_eq(after.snapshot.creative_decisions.length(), 0)
}

///|
async test "quote intake conflicting partial identity fails without overwriting or claiming complete" {
  let root = "/tmp/mooncast-intake-conflict-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "conflict-intake", "SYNTHETIC conflict intake",
  )
  let request = intake_fixture_request(service, quote)
  interrupt_intake(service, quote, request, "brief:effect")
  let before = service.get_project(quote.project.project_id)
  let original = before.snapshot.creative_artifacts[0]
  let changed = {
    ..original,
    content: "Different bytes under the same identity",
  }
  let conflict = {
    ..before,
    snapshot: { ..before.snapshot, creative_artifacts: [changed], },
  }
  save_value(service.store, project_key(before.project_id), conflict)
  try
    StudioService::new(root).convert_commercial_quote(quote.quote_id, request)
  catch {
    Conflict(code~, message=_) => assert_eq(code, "intake_seed_conflict")
    error => raise error
  } noraise {
    _ => fail("Conflicting initial identity must remain unresolved")
  }
  assert_eq(service.get_project(before.project_id), conflict)
  let dashboard = service.commercial_dashboard_projection()
  assert_eq(dashboard.conversions[0].initialization_status, Some("pending"))
  let commerce = service.commerce_application.load()
  assert_eq(commerce.conversions.length(), 1)
}

///|
async test "quote intake concurrent attempts share one conversion and seed history" {
  let root = "/tmp/mooncast-intake-concurrent-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "concurrent-intake", "SYNTHETIC concurrent intake",
  )
  let request = intake_fixture_request(service, quote)
  @async.with_task_group(group => {
    for index in 0..<6 {
      let path = if index % 2 == 0 { root } else { root + "/." }
      group.spawn_bg(() => {
        ignore(
          StudioService::new(path).convert_commercial_quote(
            quote.quote_id,
            request,
          ),
        )
      })
    }
  })
  let after = service.get_project(quote.project.project_id)
  assert_eq(after.snapshot.creative_artifacts.length(), 7)
  assert_eq(after.command_receipts.length(), 8)
  assert_eq(service.commerce_application.load().conversions.length(), 1)
  assert_eq(service.commerce_application.load().reservations.length(), 1)
}

///|
async test "quote intake HTTP resumes a plan-only interruption and repairs canonical projection failure" {
  let root = "/tmp/mooncast-intake-http-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "http-intake", "SYNTHETIC persisted HTTP intake",
  )
  let request = intake_fixture_request(service, quote)
  interrupt_intake(service, quote, request, "plan")
  assert_eq(service.commerce_application.load().conversions.length(), 0)
  let dashboard = StudioService::new(root).commercial_dashboard_projection()
  assert_eq(dashboard.conversions.length(), 1)
  assert_eq(dashboard.conversions[0].initialization_status, Some("pending"))
  let obstructed = root +
    "/application/production/production-project-" +
    quote.project.project_id +
    ".json"
  @fs.mkdir(obstructed, recursive=true)
  let response = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/commercial-intake/quotes/" + quote.quote_id + "/conversion",
    query: None,
    headers: Map([]),
    body: @utf8.encode(request.to_json().stringify()),
  })
  assert_true(response.status >= 400)
  let partial = service.get_project(quote.project.project_id)
  assert_eq(partial.snapshot.creative_artifacts.length(), 0)
  assert_eq(service.commerce_application.load().conversions.length(), 1)
  @fs.remove(obstructed)
  let restarted = StudioService::new(root)
  let resumed = restarted.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/commercial-intake/quotes/" + quote.quote_id + "/conversion",
    query: None,
    headers: Map([]),
    body: @utf8.encode(request.to_json().stringify()),
  })
  assert_eq(resumed.status, 201)
  let project = restarted.get_project(quote.project.project_id)
  assert_eq(project.snapshot.creative_artifacts.length(), 7)
  assert_eq(
    restarted.production_repository.get(project.project_id),
    Some(project.snapshot),
  )
}

///|
async test "quote intake tombstone and unrelated existing project remain unchanged" {
  let root = "/tmp/mooncast-intake-tombstone-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "deleted-intake", "SYNTHETIC deleted intake",
  )
  let request = intake_fixture_request(service, quote)
  interrupt_intake(service, quote, request, "project:checkpoint")
  let project = service.get_project(quote.project.project_id)
  service.delete_project(project.project_id, project.snapshot.revision)
  try
    StudioService::new(root).convert_commercial_quote(quote.quote_id, request)
  catch {
    Conflict(code~, message=_) => assert_eq(code, "project_tombstoned")
    error => raise error
  } noraise {
    _ => fail("Deleted project cannot be recreated")
  }
  assert_true(service.load_project_record(project.project_id).unwrap().deleted)
  let other_root = root + "-other"
  let other = StudioService::new(other_root)
  let other_quote = ledger_quote_fixture(
    other, "occupied-intake", "SYNTHETIC occupied intake",
  )
  let unrelated = other.create_project(
    @production_app.episode_production_graph(
      "occupied-intake", "Unrelated user work", 180, 5000.0,
    ),
    "existing-time",
  )
  try
    other.convert_commercial_quote(
      other_quote.quote_id,
      intake_fixture_request(other, other_quote),
    )
  catch {
    Conflict(code~, message=_) => assert_eq(code, "project_exists")
    error => raise error
  } noraise {
    _ => fail("Unrelated project cannot be converted")
  }
  assert_eq(other.get_project(unrelated.project_id), unrelated)
  assert_eq(other.commerce_application.load().conversions.length(), 0)
}

///|
async test "quote intake cannot claim a project created during interruption even with identical graph" {
  for boundary in ["plan", "conversion:effect"] {
    let root = "/tmp/mooncast-intake-ownership-" + @async.now().to_string()
    let service = StudioService::new(root)
    let quote = ledger_quote_fixture(
      service, "ownership-intake", "SYNTHETIC ownership intake",
    )
    let request = intake_fixture_request(service, quote)
    interrupt_intake(service, quote, request, boundary)
    let plan : QuoteIntakePlan = load_value(
      service.store,
      quote_intake_key(quote.project.project_id),
    ).unwrap()
    let other = service.create_project(plan.graph, plan.conversion.converted_at)
    assert_eq(other.initialization_digest, None)
    try
      StudioService::new(root).convert_commercial_quote(quote.quote_id, request)
    catch {
      Conflict(code~, message=_) => assert_eq(code, "intake_project_conflict")
      error => raise error
    } noraise {
      _ => fail("An unrelated project cannot be claimed by a pending intake")
    }
    assert_eq(service.get_project(other.project_id), other)
    assert_eq(
      service.commerce_application.load().conversions.length(),
      if boundary == "plan" {
        0
      } else {
        1
      },
    )
  }
}

///|
async test "quote intake legacy completed or partial project is never inferred as resumable" {
  let root = "/tmp/mooncast-intake-legacy-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "legacy-intake", "SYNTHETIC legacy intake",
  )
  let request = intake_fixture_request(service, quote)
  ignore(service.convert_commercial_quote(quote.quote_id, request))
  ignore(service.store.remove(quote_intake_key(quote.project.project_id)))
  let existing = service.get_project(quote.project.project_id)
  let partial = {
    ..existing,
    initialization_digest: None,
    snapshot: @kernel.empty_snapshot(existing.snapshot.graph),
    events: [],
    command_receipts: [],
  }
  ignore(
    service.store.put_json(
      project_key(existing.project_id),
      omit_null_fields(partial.to_json()),
    ),
  )
  let result = StudioService::new(root).convert_commercial_quote(
    quote.quote_id,
    request,
  )
  assert_eq(result.conversion.initialization_status, Some("legacy"))
  assert_eq(service.get_project(existing.project_id), partial)
  assert_eq(service.store.get_json(quote_intake_key(existing.project_id)), None)
}

///|
async test "quote intake resumes original conversion when capacity no longer matches and refuses rebinding" {
  let root = "/tmp/mooncast-intake-binding-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "bound-intake", "SYNTHETIC original binding",
  )
  let request = intake_fixture_request(service, quote)
  interrupt_intake(service, quote, request, "conversion:effect")
  let commerce = service.commerce_application.load()
  let store = @host_store.AtomicStore::new(root + "/application/commerce")
  ignore(
    store.put_json(
      "commercial-snapshot.json",
      { ..commerce, capacity_boards: [], }.to_json(),
    ),
  )
  try
    service.convert_commercial_quote(quote.quote_id, {
      ..request,
      expected_capacity_digest: "different",
    })
  catch {
    Conflict(code~, message=_) => assert_eq(code, "quote_conversion_conflict")
    error => raise error
  } noraise {
    _ => fail("Changed capacity cannot rebind conversion")
  }
  ignore(
    StudioService::new(root).convert_commercial_quote(quote.quote_id, request),
  )
  assert_eq(
    service.get_project(quote.project.project_id).snapshot.creative_artifacts.length(),
    7,
  )
  assert_eq(
    service.commerce_application.load().conversions,
    commerce.conversions,
  )
}

///|
async test "quote intake plan-only retry uses historical quote and capacity after newer revisions" {
  let root = "/tmp/mooncast-intake-history-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "history-intake", "SYNTHETIC historical intake",
  )
  let request = intake_fixture_request(service, quote)
  interrupt_intake(service, quote, request, "plan")
  let snapshot = service.commerce_application.load()
  let original = snapshot.quotes[0]
  let newer = {
    ..original,
    quote: {
      ..original.quote,
      version: original.quote.version + 1,
      digest: "sha256:newer-quote",
    },
  }
  let old_board = snapshot.capacity_boards[0]
  let new_board = {
    ..old_board,
    digest: "sha256:newer-capacity",
    ready: false,
  }
  let store = @host_store.AtomicStore::new(root + "/application/commerce")
  ignore(
    store.put_json(
      "commercial-snapshot.json",
      {
        ..snapshot,
        quotes: [..snapshot.quotes, newer],
        capacity_boards: [..snapshot.capacity_boards, new_board],
      }.to_json(),
    ),
  )
  let restarted = StudioService::new(root)
  let dashboard = restarted.commercial_dashboard_projection()
  assert_eq(dashboard.quotes[0].version, newer.quote.version)
  assert_eq(dashboard.conversions[0].quote_version, quote.version)
  assert_eq(
    dashboard.conversions[0].capacity_digest,
    request.expected_capacity_digest,
  )
  ignore(restarted.convert_commercial_quote(quote.quote_id, request))
  let complete = restarted.commerce_application.load()
  assert_eq(complete.conversions.length(), 1)
  assert_eq(complete.conversions[0].quote, original.quote)
  assert_eq(complete.conversions[0].capacity_digest, old_board.digest)
  assert_eq(complete.quotes.length(), 2)
}

///|
async test "quote intake reports preserved existing draft without claiming missing seeds completed" {
  let root = "/tmp/mooncast-intake-adopted-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "adopted-intake", "SYNTHETIC adopted intake",
  )
  let original = service.create_project(
    @production_app.episode_production_graph(
      quote.project.project_id,
      quote.project.title,
      quote.project.target_duration_seconds,
      quote.project.production_budget_cny,
    ),
    "original-project-time",
  )
  let request = intake_fixture_request(service, quote)
  let result = service.convert_commercial_quote(quote.quote_id, request)
  assert_eq(result.conversion.initialization_status, Some("preserved-existing"))
  assert_eq(service.get_project(original.project_id), original)
  assert_eq(
    service.store.get_json(project_experience_key(original.project_id)),
    None,
  )
  assert_eq(
    service.commercial_dashboard_projection().conversions[0].initialization_status,
    Some("preserved-existing"),
  )
  ignore(
    StudioService::new(root).convert_commercial_quote(quote.quote_id, request),
  )
  assert_eq(service.get_project(original.project_id), original)
}
