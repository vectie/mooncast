///|
fn bridge_mailbox_key(value : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(value)))[0:32].to_owned()
}

///|
fn bridge_root(workspace : String) -> String {
  workspace + "/.moonsuite/products/mooncast/pack-bridge"
}

///|
async fn bridge_ensure_parent(path : String) -> Unit {
  let parent = @path.Path::dirname(path).to_string()
  if parent == "." || parent == "" || @fs.exists(parent) {
    return
  }
  bridge_ensure_parent(parent)
  @fs.mkdir(parent, permission=0o755) catch {
    _ => ()
  }
}

///|
async fn bridge_write_json(path : String, value : Json) -> Unit {
  bridge_ensure_parent(path)
  let temporary = path + ".next"
  @fs.write_file(
    temporary,
    @encoding/utf8.encode(value.stringify(indent=2) + "\n"),
    create_mode=CreateOrTruncate,
    permission=0o644,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
async fn require_delivered_candidate(
  workspace : String,
  candidate : TownPackCandidate,
) -> String {
  let key = bridge_mailbox_key(candidate.candidate_ref)
  let path = bridge_root(workspace) + "/inbox/candidates/\{key}.json"
  guard @fs.exists(path) &&
    @json.from_json(@json.parse(@fs.read_file(path).text())) == candidate else {
    fail(
      "MoonCast candidate was not delivered through the governed pack mailbox",
    )
  }
  key
}

///|
async fn publish_projection(
  workspace : String,
  projection : PackTownProjection,
) -> PackTownProjection {
  let path = bridge_root(workspace) + "/outbox/projection.json"
  let combined = if @fs.exists(path) {
    let existing : PackTownProjection = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    )
    guard existing.pack_id == "mooncast" &&
      existing.version == projection.version else {
      fail("MoonCast projection outbox belongs to another pack version")
    }
    let subject_refs = projection.subjects.map(subject => subject.subject_ref)
    {
      ..projection,
      subjects: existing.subjects.filter(subject => {
        !subject_refs.contains(subject.subject_ref)
      }) +
      projection.subjects,
    }
  } else {
    projection
  }
  bridge_write_json(path, combined.to_json())
  combined
}

///|
/// Prepare a governed mailbox candidate as a creative brief. Receipt does not
/// imply approval, publishing, rights clearance, or delivery.
pub async fn prepare_creative_candidate(
  workspace : String,
  candidate : TownPackCandidate,
  audience : String,
  channels : Array[String],
  deliverables : Array[String],
  rights_constraints : Array[String],
  prepared_at : String,
) -> PackTownProjection {
  let key = require_delivered_candidate(workspace, candidate)
  let brief = intake_creative_candidate(
    candidate, audience, channels, deliverables, rights_constraints,
  )
  let record_ref = ".moonsuite/products/mooncast/records/creative-candidate-intake/\{key}.json"
  bridge_write_json(workspace + "/" + record_ref, brief.to_json())
  let projection = publish_projection(
    workspace,
    project_creative_brief(candidate, brief, prepared_at),
  )
  bridge_write_json(
    bridge_root(workspace) + "/outbox/candidate-receipts/\{key}.json",
    {
      "contract_id": "moontown.pack-candidate-acknowledgement.v1",
      "candidate_ref": candidate.candidate_ref,
      "pack_id": "mooncast",
      "operation_id": "creative.candidate.intake",
      "decision": "received",
      "occurred_at": prepared_at,
      "evidence_refs": [record_ref],
    },
  )
  projection
}
