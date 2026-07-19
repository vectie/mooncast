///|
pub(all) struct ProjectRepositoryEvent {
  contract : String
  project_id : String
  revision : Int
  kind : String
  evidence_digest : String
  recorded_at : String
  domain_events : Array[@kernel.ProjectEvent]
  external_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub suberror ProjectRepositoryError {
  ProjectExists(String)
  ProjectNotFound(String)
  ProjectCorrupt(String)
  ProjectRevisionConflict(String)
  ProjectCommandRejected(String)
} derive(Debug)

///|
pub struct ProjectRepository {
  store : @store.AtomicStore
}

///|
pub fn ProjectRepository::new(root : String) -> ProjectRepository {
  { store: @store.AtomicStore::new(root, max_read_bytes=67108864) }
}

///|
pub async fn ProjectRepository::recover_temporary_files(
  self : ProjectRepository,
) -> Int {
  let mut removed = 0
  for key in self.store.list_keys() {
    if key.contains(".tmp-") && self.store.remove(key) {
      removed = removed + 1
    }
  }
  removed
}

///|
fn project_key(project_id : String) -> String {
  "production-project-" + project_id + ".json"
}

///|
pub async fn ProjectRepository::create(
  self : ProjectRepository,
  snapshot : @kernel.ProjectSnapshot,
) -> @kernel.ProjectSnapshot {
  if !@project.validate_graph(snapshot.graph).valid {
    raise ProjectCorrupt(snapshot.graph.project_id)
  }
  if self.store.get_json(project_key(snapshot.graph.project_id)) is Some(_) {
    raise ProjectExists(snapshot.graph.project_id)
  }
  ignore(
    self.store.put_json(
      project_key(snapshot.graph.project_id),
      snapshot.to_json(),
    ),
  )
  let event : ProjectRepositoryEvent = {
    contract: "mooncast.project-event.v2",
    project_id: snapshot.graph.project_id,
    revision: snapshot.revision,
    kind: "project.created",
    evidence_digest: content_digest(snapshot.to_json().stringify()),
    recorded_at: @runtime.wall_clock_ms().to_string(),
    domain_events: [],
    external_effect_performed: false,
  }
  ignore(
    self.store.put_json(
      "project-event-" + snapshot.graph.project_id + "-0.json",
      event.to_json(),
    ),
  )
  snapshot
}

///|
pub async fn ProjectRepository::get(
  self : ProjectRepository,
  project_id : String,
) -> @kernel.ProjectSnapshot? {
  if !@project.valid_project_id(project_id) {
    return None
  }
  match self.store.get_json(project_key(project_id)) {
    None => None
    Some(value) => {
      let snapshot : @kernel.ProjectSnapshot = @json.from_json(value) catch {
        _ => raise ProjectCorrupt(project_id)
      }
      Some(snapshot)
    }
  }
}

///|
pub async fn ProjectRepository::list(
  self : ProjectRepository,
) -> Array[@kernel.ProjectSnapshot] {
  let projects : Array[@kernel.ProjectSnapshot] = []
  for key in self.store.list_keys(prefix="production-project-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let snapshot : @kernel.ProjectSnapshot = @json.from_json(value) catch {
          _ => continue
        }
        projects.push(snapshot)
      }
      None => ()
    }
  }
  projects
}

///|
pub async fn ProjectRepository::handle(
  self : ProjectRepository,
  command : @kernel.ProjectCommand,
) -> @kernel.CommandResult {
  let snapshot = match self.get(command.snapshot.graph.project_id) {
    Some(value) => value
    None => raise ProjectNotFound(command.snapshot.graph.project_id)
  }
  if snapshot.revision != command.snapshot.revision {
    raise ProjectRevisionConflict(snapshot.graph.project_id)
  }
  let bound = { ..command, snapshot, }
  let result = @kernel.handle(bound)
  if !result.ok {
    raise ProjectCommandRejected(result.error.unwrap().code)
  }
  for event in result.emitted_events {
    ignore(
      self.store.put_json(
        "domain-event-" +
        snapshot.graph.project_id +
        "-" +
        (snapshot.revision + 1).to_string() +
        "-" +
        event.event_id +
        ".json",
        event.to_json(),
      ),
    )
  }
  ignore(
    self.store.put_json(
      project_key(snapshot.graph.project_id),
      result.snapshot.to_json(),
    ),
  )
  let repository_event : ProjectRepositoryEvent = {
    contract: "mooncast.project-event.v2",
    project_id: snapshot.graph.project_id,
    revision: result.snapshot.revision,
    kind: command.command,
    evidence_digest: command.evidence_digest,
    recorded_at: command.recorded_at,
    domain_events: result.emitted_events,
    external_effect_performed: false,
  }
  ignore(
    self.store.put_json(
      "project-event-" +
      snapshot.graph.project_id +
      "-" +
      result.snapshot.revision.to_string() +
      ".json",
      repository_event.to_json(),
    ),
  )
  result
}

///|
/// Exact-revision replacement used by import/recovery hosts. Normal domain
/// changes must use `handle` so their typed events are retained.
pub async fn ProjectRepository::replace(
  self : ProjectRepository,
  snapshot : @kernel.ProjectSnapshot,
  expected_revision : Int,
  evidence_digest : String,
  recorded_at : String,
) -> @kernel.ProjectSnapshot {
  let current = match self.get(snapshot.graph.project_id) {
    None => raise ProjectNotFound(snapshot.graph.project_id)
    Some(value) => value
  }
  if current.revision != expected_revision ||
    snapshot.revision != expected_revision + 1 ||
    evidence_digest == "" ||
    recorded_at == "" {
    raise ProjectRevisionConflict(snapshot.graph.project_id)
  }
  ignore(
    self.store.put_json(
      project_key(snapshot.graph.project_id),
      snapshot.to_json(),
    ),
  )
  let event : ProjectRepositoryEvent = {
    contract: "mooncast.project-event.v2",
    project_id: snapshot.graph.project_id,
    revision: snapshot.revision,
    kind: "project.replaced",
    evidence_digest,
    recorded_at,
    domain_events: [],
    external_effect_performed: false,
  }
  ignore(
    self.store.put_json(
      "project-event-" +
      snapshot.graph.project_id +
      "-" +
      snapshot.revision.to_string() +
      ".json",
      event.to_json(),
    ),
  )
  snapshot
}

///|
/// Mirrors the Studio-owned canonical snapshot into the pipeline repository.
/// This is an import/recovery boundary: ordinary production mutations still
/// use typed commands through `handle`.
pub async fn ProjectRepository::synchronize_canonical(
  self : ProjectRepository,
  snapshot : @kernel.ProjectSnapshot,
  evidence_digest : String,
  recorded_at : String,
) -> @kernel.ProjectSnapshot {
  if !@project.validate_graph(snapshot.graph).valid ||
    evidence_digest == "" ||
    recorded_at == "" {
    raise ProjectCorrupt(snapshot.graph.project_id)
  }
  ignore(
    self.store.put_json(
      project_key(snapshot.graph.project_id),
      snapshot.to_json(),
    ),
  )
  let event : ProjectRepositoryEvent = {
    contract: "mooncast.project-event.v2",
    project_id: snapshot.graph.project_id,
    revision: snapshot.revision,
    kind: "project.canonical-synchronized",
    evidence_digest,
    recorded_at,
    domain_events: [],
    external_effect_performed: false,
  }
  ignore(
    self.store.put_json(
      "project-event-" +
      snapshot.graph.project_id +
      "-" +
      snapshot.revision.to_string() +
      "-canonical.json",
      event.to_json(),
    ),
  )
  snapshot
}

///|
pub async fn ProjectRepository::record_repository_event(
  self : ProjectRepository,
  project_id : String,
  kind : String,
  details_digest : String,
  recorded_at : String,
) -> ProjectRepositoryEvent {
  let snapshot = match self.get(project_id) {
    None => raise ProjectNotFound(project_id)
    Some(value) => value
  }
  if kind == "" || details_digest == "" || recorded_at == "" {
    raise ProjectCommandRejected("repository_event_invalid")
  }
  let event : ProjectRepositoryEvent = {
    contract: "mooncast.project-event.v2",
    project_id,
    revision: snapshot.revision,
    kind,
    evidence_digest: details_digest,
    recorded_at,
    domain_events: [],
    external_effect_performed: false,
  }
  ignore(
    self.store.put_json(
      "project-event-" +
      project_id +
      "-" +
      snapshot.revision.to_string() +
      "-" +
      @runtime.new_id(prefix="event") +
      ".json",
      event.to_json(),
    ),
  )
  event
}

///|
pub async fn ProjectRepository::events(
  self : ProjectRepository,
  project_id : String,
) -> Array[ProjectRepositoryEvent] {
  let events : Array[ProjectRepositoryEvent] = []
  for
    key in self.store.list_keys(
      prefix="project-event-" + project_id + "-",
      suffix=".json",
    ) {
    match self.store.get_json(key) {
      Some(value) => {
        let event : ProjectRepositoryEvent = @json.from_json(value) catch {
          _ => continue
        }
        events.push(event)
      }
      None => ()
    }
  }
  events
}
