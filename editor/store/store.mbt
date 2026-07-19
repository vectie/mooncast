///|
pub(all) struct SnapshotRecord {
  contract : String
  schema_version : Int
  project_id : String
  stored_revision : Int
  base_snapshot : @domain.EditorProject
  current_snapshot : @domain.EditorProject
  command_log : Array[@domain.CommandLogRecord]
  content_digest : String
  backup_ref : BackupRef?
  metadata : StoreMetadata
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BackupRef {
  digest : String
  path : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct StoreMetadata {
  migration_receipts : Array[String]
  recovery : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MigrationReceipt {
  contract : String
  schema_version : Int
  from_version : Int
  to_version : Int
  steps : Array[String]
  input_digest : String
  output_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RecoveryReceipt {
  contract : String
  schema_version : Int
  project_id : String
  code : String
  source_key : String
  quarantine_key : String
  recovered_revision : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EventRecord {
  contract : String
  schema_version : Int
  project_id : String
  sequence : Int
  command : @domain.EditCommand
  command_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct EditorRepository {
  snapshots : @host_store.AtomicStore
  events : @host_store.AtomicStore
  jobs : @host_store.AtomicStore
  authorities : @host_store.AtomicStore
  intakes : @host_store.AtomicStore
  reviews : @host_store.AtomicStore
  workspace : @host_store.AtomicStore
  backups : @host_store.AtomicStore
  quarantine : @host_store.AtomicStore
}

///|
pub fn EditorRepository::new(root : String) -> EditorRepository {
  {
    snapshots: @host_store.AtomicStore::new(root + "/snapshots"),
    events: @host_store.AtomicStore::new(root + "/events"),
    jobs: @host_store.AtomicStore::new(root + "/jobs"),
    authorities: @host_store.AtomicStore::new(root + "/preview-authorities"),
    intakes: @host_store.AtomicStore::new(root + "/media-intakes"),
    reviews: @host_store.AtomicStore::new(root + "/reviews"),
    workspace: @host_store.AtomicStore::new(root + "/workspace"),
    backups: @host_store.AtomicStore::new(root + "/backups"),
    quarantine: @host_store.AtomicStore::new(root + "/quarantine"),
  }
}

///|
fn snapshot_key(project_id : String) -> String {
  "project-" + project_id + ".json"
}

///|
fn event_key(project_id : String, sequence : Int) -> String {
  "event-" + project_id + "-" + sequence.to_string() + ".json"
}

///|
fn command_digest(command : @domain.EditCommand) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @utf8.encode(@domain.legacy_command_json(command).stringify()),
    ),
  )
}

///|
pub async fn EditorRepository::save_session(
  self : EditorRepository,
  session : @domain.EditorSession,
  content_digest : String,
) -> SnapshotRecord {
  let record : SnapshotRecord = {
    contract: "mooncast.editor-store-record.v1",
    schema_version: 1,
    project_id: session.snapshot.project_id,
    stored_revision: session.snapshot.revision,
    base_snapshot: session.initial,
    current_snapshot: session.snapshot,
    command_log: session.command_log,
    content_digest,
    backup_ref: None,
    metadata: { migration_receipts: [], recovery: [] },
  }
  ignore(
    self.snapshots.put_json(snapshot_key(record.project_id), record.to_json()),
  )
  if session.command_log.last() is Some(entry) {
    let persisted : EventRecord = {
      contract: "mooncast.editor-command-log-record.v1",
      schema_version: 1,
      project_id: record.project_id,
      sequence: session.command_log.length(),
      command: entry.command,
      command_digest: command_digest(entry.command),
    }
    ignore(
      self.events.put_json(
        event_key(record.project_id, persisted.sequence),
        persisted.to_json(),
      ),
    )
  }
  record
}

///|
pub async fn EditorRepository::load_snapshot(
  self : EditorRepository,
  project_id : String,
) -> SnapshotRecord? {
  match self.snapshots.get_json(snapshot_key(project_id)) {
    None => None
    Some(value) => Some(@json.from_json(value))
  }
}

///|
pub async fn EditorRepository::list_snapshots(
  self : EditorRepository,
) -> Array[SnapshotRecord] {
  let records : Array[SnapshotRecord] = []
  for key in self.snapshots.list_keys(prefix="project-", suffix=".json") {
    if self.snapshots.get_json(key) is Some(value) {
      records.push(@json.from_json(value))
    }
  }
  records.sort_by((left, right) => left.project_id.compare(right.project_id))
  records
}

///|
pub async fn EditorRepository::load_events(
  self : EditorRepository,
  project_id : String,
) -> Array[EventRecord] {
  let keys = self.events.list_keys(
    prefix="event-" + project_id + "-",
    suffix=".json",
  )
  let records : Array[EventRecord] = []
  for key in keys {
    if self.events.get_json(key) is Some(value) {
      records.push(@json.from_json(value))
    }
  }
  records
}

///|
pub async fn EditorRepository::replay(
  self : EditorRepository,
  initial : @domain.EditorProject,
) -> @domain.EditorSession {
  match self.load_snapshot(initial.project_id) {
    Some(record) =>
      @domain.replay(
        record.base_snapshot,
        record.command_log.map(entry => entry.command),
      )
    None => {
      let records = self.load_events(initial.project_id)
      @domain.replay(initial, records.map(record => record.command))
    }
  }
}

///|
pub async fn[T : ToJson] EditorRepository::put_job(
  self : EditorRepository,
  key : String,
  value : T,
) -> Unit {
  ignore(self.jobs.put_json("job-" + key + ".json", value.to_json()))
}

///|
pub async fn[T : FromJson] EditorRepository::get_job(
  self : EditorRepository,
  key : String,
) -> T? {
  match self.jobs.get_json("job-" + key + ".json") {
    None => None
    Some(value) => Some(@json.from_json(value))
  }
}

///|
pub async fn[T : FromJson] EditorRepository::list_jobs(
  self : EditorRepository,
  project_id : String,
) -> Array[T] {
  let result : Array[T] = []
  for
    key in self.jobs.list_keys(prefix="job-" + project_id + "-", suffix=".json") {
    if self.jobs.get_json(key) is Some(value) {
      result.push(@json.from_json(value))
    }
  }
  result
}

///|
pub async fn[T : ToJson] EditorRepository::put_authority(
  self : EditorRepository,
  project_id : String,
  job_id : String,
  value : T,
) -> Unit {
  let key = "authority-" + project_id + "-" + job_id + ".json"
  if self.authorities.get_json(key) is Some(existing) {
    guard existing == value.to_json() else {
      fail("preview authority conflict")
    }
    return
  }
  ignore(self.authorities.put_json(key, value.to_json()))
}

///|
pub async fn[T : FromJson] EditorRepository::get_authority(
  self : EditorRepository,
  project_id : String,
  job_id : String,
) -> T? {
  match
    self.authorities.get_json(
      "authority-" + project_id + "-" + job_id + ".json",
    ) {
    None => None
    Some(value) => Some(@json.from_json(value))
  }
}

///|
pub async fn[T : ToJson] EditorRepository::put_intake(
  self : EditorRepository,
  project_id : String,
  intake_id : String,
  value : T,
) -> Unit {
  ignore(
    self.intakes.put_json(
      "intake-" + project_id + "-" + intake_id + ".json",
      value.to_json(),
    ),
  )
}

///|
pub async fn[T : FromJson] EditorRepository::get_intake(
  self : EditorRepository,
  project_id : String,
  intake_id : String,
) -> T? {
  match
    self.intakes.get_json("intake-" + project_id + "-" + intake_id + ".json") {
    None => None
    Some(value) => Some(@json.from_json(value))
  }
}

///|
pub async fn[T : FromJson] EditorRepository::list_intakes(
  self : EditorRepository,
  project_id : String,
) -> Array[T] {
  let result : Array[T] = []
  for
    key in self.intakes.list_keys(
      prefix="intake-" + project_id + "-",
      suffix=".json",
    ) {
    if self.intakes.get_json(key) is Some(value) {
      result.push(@json.from_json(value))
    }
  }
  result
}

///|
pub async fn[T : ToJson] EditorRepository::put_review(
  self : EditorRepository,
  project_id : String,
  comment_id : String,
  value : T,
) -> Unit {
  let key = "review-" + project_id + "-" + comment_id + ".json"
  if self.reviews.get_json(key) is Some(existing) {
    guard existing == value.to_json() else {
      fail("review comment idempotency conflict")
    }
    return
  }
  ignore(self.reviews.put_json(key, value.to_json()))
}

///|
pub async fn[T : FromJson] EditorRepository::list_reviews(
  self : EditorRepository,
  project_id : String,
) -> Array[T] {
  let result : Array[T] = []
  for
    key in self.reviews.list_keys(
      prefix="review-" + project_id + "-",
      suffix=".json",
    ) {
    if self.reviews.get_json(key) is Some(value) {
      result.push(@json.from_json(value))
    }
  }
  result
}

///|
pub async fn[T : ToJson] EditorRepository::put_workspace(
  self : EditorRepository,
  project_id : String,
  name : String,
  value : T,
) -> Unit {
  let key = "workspace-" + project_id + "-" + name + ".json"
  if self.workspace.get_json(key) is Some(existing) {
    guard existing == value.to_json() else {
      fail("immutable workspace record conflict")
    }
    return
  }
  ignore(self.workspace.put_json(key, value.to_json()))
}

///|
pub async fn[T : FromJson] EditorRepository::get_workspace(
  self : EditorRepository,
  project_id : String,
  name : String,
) -> T? {
  match
    self.workspace.get_json("workspace-" + project_id + "-" + name + ".json") {
    None => None
    Some(value) => Some(@json.from_json(value))
  }
}

///|
pub async fn EditorRepository::backup(
  self : EditorRepository,
  project_id : String,
  digest : String,
) -> BackupRef {
  guard self.load_snapshot(project_id) is Some(record) else {
    fail("editor snapshot does not exist")
  }
  let hex = if digest.has_prefix("sha256:") {
    digest[7:].to_owned()
  } else {
    digest
  }
  let key = "backup-" + hex + ".json"
  ignore(self.backups.put_json(key, record.to_json()))
  { digest: hex, path: "backups/" + hex + ".json" }
}

///|
pub async fn EditorRepository::resolve_backup(
  self : EditorRepository,
  reference : BackupRef,
) -> SnapshotRecord {
  guard self.backups.get_json("backup-" + reference.digest + ".json")
    is Some(value) else {
    fail("editor backup does not exist")
  }
  @json.from_json(value)
}

///|
pub async fn EditorRepository::recover(
  self : EditorRepository,
) -> Array[RecoveryReceipt] {
  let receipts : Array[RecoveryReceipt] = []
  let keys = self.snapshots.list_keys(prefix="project-", suffix=".json")
  for key in keys {
    let parsed = self.snapshots.get_json(key) catch { _ => None }
    match parsed {
      Some(value) => {
        let record : SnapshotRecord = @json.from_json(value) catch {
          _ => {
            if self.snapshots.get_blob(key) is Some(blob) {
              let q = "corrupt-" + blob.sha256 + ".json"
              ignore(self.quarantine.put_blob(q, blob.bytes))
              receipts.push({
                contract: "mooncast.editor-recovery-receipt.v1",
                schema_version: 1,
                project_id: key,
                code: "corrupt-envelope-quarantined",
                source_key: key,
                quarantine_key: q,
                recovered_revision: 0,
              })
            }
            continue
          }
        }
        let replayed = @domain.replay(
          record.base_snapshot,
          record.command_log.map(entry => entry.command),
        )
        if replayed.snapshot != record.current_snapshot {
          let recovery = record.metadata.recovery.copy()
          recovery.push("journal-replayed")
          let repaired = {
            ..record,
            current_snapshot: replayed.snapshot,
            stored_revision: replayed.snapshot.revision,
            metadata: { ..record.metadata, recovery, },
          }
          ignore(self.snapshots.put_json(key, repaired.to_json()))
          receipts.push({
            contract: "mooncast.editor-recovery-receipt.v1",
            schema_version: 1,
            project_id: record.project_id,
            code: "journal-replayed",
            source_key: key,
            quarantine_key: "",
            recovered_revision: repaired.stored_revision,
          })
        }
      }
      None => ()
    }
  }
  receipts
}

///|
fn json_digest(value : Json) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value.stringify())))
}

///|
pub fn migrate_document(value : Json) -> (Json, MigrationReceipt) raise {
  let input_digest = json_digest(value)
  guard value is Object(fields) else {
    fail("migration input must be an object")
  }
  let mut from_version = 1
  let steps : Array[String] = []
  let migrated = fields.copy()
  if fields.get("contract") == Some("mooncast.editor-project.v0".to_json()) {
    from_version = 0
    guard fields.get("timeline") is Some(Object(timeline)) else {
      fail("legacy timeline is required")
    }
    guard timeline.get("fps") is Some(fps) else {
      fail("legacy fps is required")
    }
    let next_timeline = timeline.copy()
    ignore(next_timeline.remove("fps"))
    next_timeline["timebase"] = Json::object({ "ticks_per_second": fps })
    migrated["timeline"] = Json::object(next_timeline)
    migrated["contract"] = "mooncast.editor-project.v1".to_json()
    ignore(migrated.remove("schema_version"))
    steps.push("v0_to_v1")
  } else {
    guard fields.get("contract") == Some("mooncast.editor-project.v1".to_json()) else {
      fail("unknown editor schema version")
    }
  }
  let output = Json::object(migrated)
  (
    output,
    {
      contract: "mooncast.editor-migration-receipt.v1",
      schema_version: 1,
      from_version,
      to_version: 1,
      steps,
      input_digest,
      output_digest: json_digest(output),
    },
  )
}
