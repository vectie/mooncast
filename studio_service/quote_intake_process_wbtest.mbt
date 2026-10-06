///|
// The native test executable also serves as an isolated fixture worker. This
// launches no server/provider and only touches the root created by its parent.
async test "quote intake process fixture worker" {
  let args = @env.args()
  guard args.length() == 6 else { return }
  let service = StudioService::new(args[2])
  let request : QuoteConversionInput = @json.from_json(@json.parse(args[4]))
  if args[5] == "interrupt" {
    try
      service.convert_quote_intake(args[3], request, async fn(step) {
        if step == "metadata:effect" {
          save_value(service.store, "process-interrupted.json", step)
          raise IntakeFixtureInterruption(step)
        }
      })
    catch {
      IntakeFixtureInterruption(_) => ()
      error => raise error
    } noraise {
      _ => fail("Expected process to exit after persisted metadata")
    }
    return
  }
  for attempt in 0..<200 {
    try
      service.convert_quote_intake(args[3], request, async fn(step) {
        if step == "qualification:effect" {
          @async.sleep(20)
        }
      })
    catch {
      Conflict(code="intake_in_progress", message=_) => @async.sleep(10)
      error => raise error
    } noraise {
      _ => return
    }
    if attempt == 199 {
      fail("Concurrent fixture did not release the intake lock")
    }
  }
}

///|
async test "quote intake separate processes resume persisted failure with one identity" {
  let root = "/tmp/mooncast-intake-process-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "process-intake", "SYNTHETIC cross-process intake",
  )
  let request = intake_fixture_request(service, quote)
  let executable = @env.args()[0]
  async fn run_worker(mode : String) -> Unit {
    let result = @process.run_capture({
      executable,
      arguments: [
        "quote_intake_process_wbtest.mbt:0-1",
        root,
        quote.quote_id,
        request.to_json().stringify(),
        mode,
      ],
      working_directory: None,
      timeout_ms: 15000,
      max_output_bytes: 65536,
    })
    assert_eq(result.exit_code, Some(0), msg=@utf8.decode(result.stderr))
    assert_false(result.timed_out)
    let output = @utf8.decode(result.stdout)
    assert_true(output.contains("\"message\":\"\""), msg=output)
  }
  run_worker("interrupt")
  assert_eq(
    service.get_project(quote.project.project_id).snapshot.creative_artifacts.length(),
    0,
  )
  assert_true(service.store.get_json("process-interrupted.json") is Some(_))
  @async.with_task_group(group => {
    for _ in 0..<6 {
      group.spawn_bg(() => run_worker("resume"))
    }
  })
  let project = service.get_project(quote.project.project_id)
  assert_eq(project.snapshot.creative_artifacts.length(), 7)
  assert_eq(project.command_receipts.length(), 8)
  assert_eq(service.commerce_application.load().conversions.length(), 1)
  assert_eq(service.commerce_application.load().reservations.length(), 1)
  assert_eq(
    service.production_repository.get(project.project_id),
    Some(project.snapshot),
  )
}
