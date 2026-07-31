///|
fn utility_concat_job_for_resume_test(
  inputs : Array[UtilityConcatJobInput],
) -> UtilityConcatJob {
  {
    contract: "mooncast.editor-utility-concat-job.v1",
    job_id: "utility-concat-resume-test",
    idempotency_key: "utility-concat-resume-test",
    state: "awaiting-inputs",
    inputs,
    uploaded_count: inputs.filter(input => input.uploaded).length(),
    expected_count: inputs.length(),
    output_digest: "",
    output_size: 0,
    media_url: "",
    error: "",
    created_by: "test",
    created_at: "2026-07-23T00:00:00Z",
    updated_at: "2026-07-23T00:00:00Z",
    publication_authority: false,
    provider_authority: false,
  }
}

///|
fn utility_concat_job_input_for_resume_test(
  index : Int,
  uploaded : Bool,
) -> UtilityConcatJobInput {
  {
    index,
    file_name: "clip-\{index}.mp4",
    mime_type: "video/mp4",
    size_bytes: index + 1,
    sha256: "sha256:test-\{index}",
    uploaded,
  }
}

///|
test "utility concat resume selects the first missing index, not upload count" {
  let job = utility_concat_job_for_resume_test([
    utility_concat_job_input_for_resume_test(0, false),
    utility_concat_job_input_for_resume_test(1, true),
    utility_concat_job_input_for_resume_test(2, false),
  ])
  guard job.next_pending_input() is Some(next) else {
    fail("expected a pending utility concat input")
  }
  inspect(job.uploaded_count, content="1")
  inspect(next.index, content="0")
}

///|
test "utility concat resume reports no input after every upload" {
  let job = utility_concat_job_for_resume_test([
    utility_concat_job_input_for_resume_test(0, true),
    utility_concat_job_input_for_resume_test(1, true),
  ])
  inspect(job.next_pending_input() is None, content="true")
}
