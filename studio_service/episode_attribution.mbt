///|
struct EpisodeAttributionInput {
  command_id : String
  expected_project_revision : Int
  expected_ledger_revision : Int
  expected_actuals_digest : String?
  category : String
  value : Double
  evidence_ref : String
  author : String
  note : String
  supersedes_id : String?
  supersedes_digest : String?
  human_confirmed : Bool
} derive(ToJson, FromJson, Eq, Debug)

///|
struct EpisodeAttributionRecord {
  record_id : String
  project_id : String
  episode_id : String
  input : EpisodeAttributionInput
  recorded_at : String
  digest : String
} derive(ToJson, FromJson, Eq, Debug)

///|
fn episode_attribution_key(project_id : String) -> String {
  "episode-attribution-" + project_id + ".json"
}

///|
async fn StudioService::episode_attribution_records(
  self : StudioService,
  project_id : String,
) -> Array[EpisodeAttributionRecord] {
  let records : Array[EpisodeAttributionRecord] = load_value(
    self.store,
    episode_attribution_key(project_id),
  ).unwrap_or([])
  for index, record in records {
    guard record.project_id == project_id &&
      record.input.expected_ledger_revision == index &&
      record.digest ==
      tower_digest({ ..record, digest: "", }.to_json().stringify()) else {
      raise Conflict(
        code="episode_attribution_integrity",
        message="Saved attribution history is inconsistent; repair requires separate review.",
      )
    }
  }
  records
}

///|
fn effective_attributions(
  records : Array[EpisodeAttributionRecord],
) -> Array[EpisodeAttributionRecord] {
  records.filter(record => {
    !records.any(next => next.input.supersedes_id == Some(record.record_id))
  })
}

///|
fn attribution_total(
  actuals : @control_tower.OperatingActuals?,
  category : String,
) -> Double? {
  guard actuals is Some(actuals) else { return None }
  match category {
    "provider_cny" =>
      if actuals.provider_cost_reconciled {
        actuals.provider_cost_confirmed_cny
      } else {
        None
      }
    "labor_cny" => actuals.labor_cost_cny
    "other_cny" => actuals.other_cost_cny
    "founder_hours" => actuals.founder_hours
    _ => None
  }
}

///|
async fn StudioService::episode_attribution_actuals(
  self : StudioService,
  project_id : String,
) -> @control_tower.OperatingActuals? {
  let actuals = self.control_tower_actuals(project_id)
  guard actuals.map(value => value.project_id == project_id).unwrap_or(true) else {
    raise Conflict(
      code="episode_attribution_project_evidence_conflict",
      message="Project actual evidence belongs to another project. Reconcile that evidence before attributing costs.",
    )
  }
  actuals
}

///|
async fn StudioService::record_episode_attribution(
  self : StudioService,
  project_id : String,
  episode_id : String,
  input : EpisodeAttributionInput,
) -> EpisodeAttributionRecord {
  self.with_mutation_lock(() => {
    let project = self.get_project(project_id)
    guard project.snapshot.graph.episodes.any(episode => {
      episode.episode_id == episode_id
    }) else {
      raise NotFound(entity="episode", id=episode_id)
    }
    let records = self.episode_attribution_records(project_id)
    match
      records
      .iter()
      .find_first(record => record.input.command_id == input.command_id) {
      Some(record) => {
        guard record.episode_id == episode_id && record.input == input else {
          raise Conflict(
            code="episode_attribution_command_conflict",
            message="Command ID already identifies different attribution evidence.",
          )
        }
        return record
      }
      None => ()
    }
    guard input.human_confirmed &&
      valid_id(input.command_id) &&
      ["provider_cny", "labor_cny", "other_cny", "founder_hours"].contains(
        input.category,
      ) &&
      input.value >= 0.0 &&
      input.value <= 1000000000.0 &&
      input.author.trim() != "" &&
      input.author.length() <= 200 &&
      input.evidence_ref.trim() != "" &&
      input.evidence_ref.trim() == input.evidence_ref &&
      input.evidence_ref.length() <= 2000 &&
      input.note.trim() != "" &&
      input.note.length() <= 4000 else {
      raise Invalid(
        code="episode_attribution_invalid",
        message="Confirm a named author, distinct evidence reference, note and finite nonnegative actual value in a supported category.",
      )
    }
    let actuals = self.episode_attribution_actuals(project_id)
    guard input.expected_project_revision == project.snapshot.revision &&
      input.expected_ledger_revision == records.length() &&
      input.expected_actuals_digest == actuals.map(value => value.digest) else {
      raise Conflict(
        code="episode_attribution_revision_conflict",
        message="Project, attribution history or project actuals changed. Reload and review before recording.",
      )
    }
    let effective = effective_attributions(records)
    match (input.supersedes_id, input.supersedes_digest) {
      (None, None) => ()
      (Some(id), Some(digest)) => {
        guard effective.any(record => {
          record.record_id == id &&
          record.digest == digest &&
          record.episode_id == episode_id &&
          record.input.category == input.category
        }) else {
          raise Conflict(
            code="episode_attribution_correction_conflict",
            message="Correction must name the exact effective record in this episode and category. History is never overwritten.",
          )
        }
      }
      _ =>
        raise Invalid(
          code="episode_attribution_correction_invalid",
          message="A correction requires both predecessor ID and digest.",
        )
    }
    let remaining = effective.filter(record => {
      Some(record.record_id) != input.supersedes_id
    })
    guard !remaining.any(record => {
      record.input.evidence_ref == input.evidence_ref
    }) else {
      raise Conflict(
        code="episode_attribution_evidence_conflict",
        message="This evidence reference is already attributed. Use a distinct evidenced line item or explicitly correct that record.",
      )
    }
    let same_category = remaining.filter(record => {
      record.input.category == input.category
    })
    let total = attribution_total(actuals, input.category)
    if actuals
      .map(value => value.project_revision == project.snapshot.revision)
      .unwrap_or(false) &&
      same_category.all(record => {
        record.input.expected_project_revision == project.snapshot.revision &&
        record.input.expected_actuals_digest == input.expected_actuals_digest
      }) {
      match total {
        Some(total) if same_category.fold(init=input.value, (sum, record) => {
            sum + record.input.value
          }) >
          total + 0.0000001 =>
          raise Conflict(
            code="episode_attribution_exceeds_total",
            message="Attribution exceeds the known comparable project total. Correct evidence before recording.",
          )
        _ => ()
      }
    }
    let core : EpisodeAttributionRecord = {
      record_id: "attribution-" +
      sha256_text(project_id + ":" + episode_id + ":" + input.command_id),
      project_id,
      episode_id,
      input,
      recorded_at: now_string(),
      digest: "",
    }
    let record = { ..core, digest: tower_digest(core.to_json().stringify()), }
    // One atomic rename commits the append, command receipt and correction link
    // together. A failed write leaves the complete previous history intact.
    save_value(
      self.store,
      episode_attribution_key(project_id),
      [..records, record],
    )
    record
  })
}

///|
async fn StudioService::episode_attribution_view(
  self : StudioService,
  project_id : String,
  episode_id : String,
) -> Json {
  self.with_mutation_lock(() => {
    self.episode_attribution_view_unlocked(project_id, episode_id)
  })
}

///|
async fn StudioService::episode_attribution_view_unlocked(
  self : StudioService,
  project_id : String,
  episode_id : String,
) -> Json {
  let project = self.get_project(project_id)
  guard project.snapshot.graph.episodes.any(episode => {
    episode.episode_id == episode_id
  }) else {
    raise NotFound(entity="episode", id=episode_id)
  }
  let records = self.episode_attribution_records(project_id)
  let effective = effective_attributions(records)
  let raw_actuals = self.control_tower_actuals(project_id)
  let foreign_actuals = raw_actuals
    .map(value => value.project_id != project_id)
    .unwrap_or(false)
  let actuals = raw_actuals.filter(value => value.project_id == project_id)
  let rows = ["provider_cny", "labor_cny", "other_cny", "founder_hours"].map(category => {
    let selected = effective.filter(record => record.input.category == category)
    let episode = selected.filter(record => record.episode_id == episode_id)
    let total = attribution_total(actuals, category)
    let attributed = selected.fold(init=0.0, (sum, record) => {
      sum + record.input.value
    })
    let comparable = actuals
      .map(value => value.project_revision == project.snapshot.revision)
      .unwrap_or(false) &&
      selected.all(record => {
        record.input.expected_project_revision == project.snapshot.revision &&
        record.input.expected_actuals_digest ==
        actuals.map(value => value.digest)
      })
    let status = if foreign_actuals {
      "held-cross-project-evidence"
    } else if total is None {
      "held-project-total-unknown"
    } else if !comparable {
      "held-stale-or-mixed-evidence-basis"
    } else if total
      .map(value => attributed > value + 0.0000001)
      .unwrap_or(false) {
      "held-over-attributed"
    } else {
      "comparable"
    }
    Json::object({
      "category": category.to_json(),
      "project_total": ledger_optional_json(total),
      "recorded_attributed_total": attributed.to_json(),
      "episode_recorded_value": if episode.is_empty() {
        Json::null()
      } else {
        episode
        .fold(init=0.0, (sum, record) => sum + record.input.value)
        .to_json()
      },
      "unallocated_remainder": if status == "comparable" {
        ledger_optional_json(total.map(value => (value - attributed).max(0.0)))
      } else {
        Json::null()
      },
      "status": status.to_json(),
    })
  })
  Json::object({
    "contract": "mooncast.episode-actual-attribution.v1".to_json(),
    "project_id": project_id.to_json(),
    "episode_id": episode_id.to_json(),
    "project_revision": project.snapshot.revision.to_json(),
    "ledger_revision": records.length().to_json(),
    "actuals_digest": ledger_optional_json(actuals.map(value => value.digest)),
    "effective_records": effective
    .filter(record => record.episode_id == episode_id)
    .to_json(),
    "history": records
    .filter(record => record.episode_id == episode_id)
    .to_json(),
    "reconciliation": rows.to_json(),
    "author_identity_verified": false.to_json(),
    "payment_effect_performed": false.to_json(),
  })
}
