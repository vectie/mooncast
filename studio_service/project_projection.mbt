///|
struct ProjectExperienceMetadata {
  objective : String
  audience : String
  channels : Array[String]
  rights_owner : String
  rights_confirmed : Bool
} derive(ToJson, FromJson)

///|
/// Normalize HTTP projections to the shape MoonBit's derived `FromJson`
/// expects for optional struct fields: absence represents `None`. Canonical
/// domain records may still persist explicit JSON nulls; this function is only
/// applied at the UI projection boundary.
pub fn omit_null_fields(value : Json) -> Json {
  match value {
    Null => Json::null()
    Array(values) => Json::array(values.map(omit_null_fields))
    Object(fields) => {
      let normalized : Map[String, Json] = {}
      for key, child in fields {
        match child {
          Null => ()
          _ => normalized[key] = omit_null_fields(child)
        }
      }
      Json::object(normalized)
    }
    other => other
  }
}

///|
fn project_experience_key(project_id : String) -> String {
  "project-experience-" + sha256_text(project_id) + ".json"
}

///|
pub async fn StudioService::save_project_experience(
  self : StudioService,
  project_id : String,
  metadata : ProjectExperienceMetadata,
) -> Unit {
  save_value(self.store, project_experience_key(project_id), metadata)
}

///|
async fn StudioService::record_initial_draft(
  self : StudioService,
  project_id : String,
  kind : @creative.ArtifactKind,
  dependency_digests : Array[String],
  content : Json,
  duration_seconds : Int?,
  expected_cost_cny : Double?,
  rights_cleared : Bool,
  recorded_at : String,
) -> @creative.CreativeArtifact {
  let record = self.get_project(project_id)
  let content_text = content.stringify()
  let kind_name = kind.to_string()
  let digest = "sha256:" +
    sha256_text(
      project_id +
      ":" +
      kind_name +
      ":1:" +
      dependency_digests.join(":") +
      ":" +
      content_text,
    )
  let artifact : @creative.CreativeArtifact = {
    reference: { id: project_id + "-" + kind_name, version: 1, digest },
    kind,
    dependency_digests,
    duration_seconds,
    expected_cost_cny,
    rights_cleared,
    content: content_text,
  }
  ignore(
    self.record_creative_artifact(project_id, {
      expected_revision: record.snapshot.revision,
      command_id: "initial-" +
      kind_name +
      "-" +
      sha256_text(project_id)[:12].to_owned(),
      recorded_at,
      evidence_digest: digest,
      artifact,
    }),
  )
  artifact
}

///|
pub async fn StudioService::seed_initial_creative_drafts(
  self : StudioService,
  project_id : String,
  metadata : ProjectExperienceMetadata,
  recorded_at : String,
  moonwiki_intake? : @intake.MoonWikiNeedsPacket,
) -> ProjectRecord {
  let initial = self.get_project(project_id)
  let existing = if initial.snapshot.qualification is None {
    match moonwiki_intake {
      Some(packet) =>
        self.record_project_qualification(
          project_id,
          metadata,
          recorded_at,
          moonwiki_intake=packet,
        ).project
      None =>
        self.record_project_qualification(project_id, metadata, recorded_at).project
    }
  } else {
    initial
  }
  if !existing.snapshot.creative_artifacts.is_empty() {
    return existing
  }
  let graph = existing.snapshot.graph
  let intake_validation = moonwiki_intake.map(@intake.validate_intake)
  let intake_context = match (moonwiki_intake, intake_validation) {
    (Some(packet), Some(validation)) =>
      Json::object({
        "contract": packet.contract.to_json(),
        "packet_id": packet.packet_id.to_json(),
        "packet_version": packet.packet_version.to_json(),
        "provenance_digest": validation.provenance_digest.to_json(),
        "evidence_refs": packet.evidence_refs.to_json(),
        "client_need": packet.client_need.to_json(),
        "contract_boundary": packet.contract_boundary.to_json(),
        "constraints": packet.constraints.to_json(),
        "creative_strategy": packet.creative_strategy.to_json(),
      })
    _ => Json::null()
  }
  let brief = self.record_initial_draft(
    project_id,
    @creative.Brief,
    [],
    Json::object({
      "objective": metadata.objective.to_json(),
      "audience": metadata.audience.to_json(),
      "channels": metadata.channels.to_json(),
      "moonwiki_intent_ref": moonwiki_intake
      .map(packet => packet.intent_refs.brief.to_json())
      .unwrap_or(Json::null()),
      "approved_needs_intake": intake_context,
      "acceptance": [
        "Approved 3-8 minute master", "Rights and provenance package", "Client milestone decision",
      ].to_json(),
    }),
    None,
    None,
    false,
    recorded_at,
  )
  let rights = self.record_initial_draft(
    project_id,
    @creative.RightsLedger,
    [brief.reference.digest],
    Json::object({
      "owner": metadata.rights_owner.to_json(),
      "confirmed": metadata.rights_confirmed.to_json(),
      "records": [
        Json::object({
          "record_id": (project_id + "-rights-001").to_json(),
          "subject": "Project source material and commissioned production".to_json(),
          "basis": "Named owner confirmation required".to_json(),
          "territory": "contract-defined".to_json(),
          "channels": metadata.channels.to_json(),
          "status": (if metadata.rights_confirmed {
            "cleared"
          } else {
            "pending"
          }).to_json(),
        }),
      ].to_json(),
    }),
    None,
    None,
    metadata.rights_confirmed,
    recorded_at,
  )
  let bible = self.record_initial_draft(
    project_id,
    @creative.IpBible,
    [rights.reference.digest],
    Json::object({
      "world": (graph.title + " production world").to_json(),
      "characters": Json::array([]),
      "style": "Define the reusable visual, camera, color, voice, and motion system.".to_json(),
      "environment_rules": [
        "Preserve approved character and location identity across shots",
      ].to_json(),
      "negative_constraints": [
        "No unlicensed likeness, voice, music, font, or trademark",
      ].to_json(),
      "moonwiki_intent_ref": moonwiki_intake
      .map(packet => packet.intent_refs.bible.to_json())
      .unwrap_or(Json::null()),
      "intake_provenance_digest": intake_validation
      .map(value => value.provenance_digest.to_json())
      .unwrap_or(Json::null()),
    }),
    None,
    None,
    false,
    recorded_at,
  )
  let script_scenes : Array[Json] = []
  for episode in graph.episodes {
    for scene in episode.scenes {
      let duration = scene.shots.fold(init=0, (total, shot) => {
        total + shot.duration_ms / 1000
      })
      script_scenes.push(
        Json::object({
          "scene_id": scene.scene_id.to_json(),
          "heading": scene.title.to_json(),
          "summary": ("Develop " +
          scene.title +
          " against the approved objective.").to_json(),
          "duration_seconds": duration.to_json(),
          "characters": Json::array([]),
          "props": Json::array([]),
          "locations": scene.shots.map(shot => shot.location_id).to_json(),
          "transition_out": "cut".to_json(),
          "audio_cues": Json::array([]),
        }),
      )
    }
  }
  let script = self.record_initial_draft(
    project_id,
    @creative.Script,
    [bible.reference.digest],
    Json::object({
      "bible_digest": bible.reference.digest.to_json(),
      "moonwiki_intent_ref": moonwiki_intake
      .map(packet => packet.intent_refs.script.to_json())
      .unwrap_or(Json::null()),
      "intake_provenance_digest": intake_validation
      .map(value => value.provenance_digest.to_json())
      .unwrap_or(Json::null()),
      "text": metadata.objective.to_json(),
      "scenes": script_scenes.to_json(),
    }),
    Some(graph.target_duration_seconds),
    None,
    false,
    recorded_at,
  )
  let claims = self.record_initial_draft(
    project_id,
    @creative.ClaimsLedger,
    [script.reference.digest],
    Json::object({
      "script_digest": script.reference.digest.to_json(),
      "claims": Json::array([]),
    }),
    None,
    None,
    false,
    recorded_at,
  )
  let board_scenes : Array[Json] = []
  for episode in graph.episodes {
    for scene in episode.scenes {
      board_scenes.push(
        Json::object({
          "scene_id": scene.scene_id.to_json(),
          "shots": scene.shots
          .map(shot => {
            Json::object({
              "shot_id": shot.shot_id.to_json(),
              "description": (graph.title + " — " + scene.title).to_json(),
              "duration_seconds": (shot.duration_ms.to_double() / 1000.0).to_json(),
              "framing": "medium".to_json(),
              "characters": shot.character_ids.to_json(),
              "props": Json::array([]),
              "location": shot.location_id.to_json(),
              "transition": "cut".to_json(),
              "audio_cues": Json::array([]),
            })
          })
          .to_json(),
        }),
      )
    }
  }
  let storyboard = self.record_initial_draft(
    project_id,
    @creative.Storyboard,
    [script.reference.digest, claims.reference.digest],
    Json::object({
      "script_digest": script.reference.digest.to_json(),
      "claims_digest": claims.reference.digest.to_json(),
      "scenes": board_scenes.to_json(),
    }),
    Some(graph.target_duration_seconds),
    None,
    false,
    recorded_at,
  )
  ignore(
    self.record_initial_draft(
      project_id,
      @creative.Animatic,
      [storyboard.reference.digest],
      Json::object({
        "storyboard_digest": storyboard.reference.digest.to_json(),
        "expected_duration_seconds": graph.target_duration_seconds.to_json(),
        "expected_cost_cny": 0.0.to_json(),
        "timing_notes": "Approve the timed animatic before expensive provider generation.".to_json(),
      }),
      Some(graph.target_duration_seconds),
      Some(0.0),
      false,
      recorded_at,
    ),
  )
  self.get_project(project_id)
}

///|
async fn StudioService::project_experience(
  self : StudioService,
  record : ProjectRecord,
) -> ProjectExperienceMetadata {
  let stored : ProjectExperienceMetadata? = load_value(
    self.store,
    project_experience_key(record.project_id),
  )
  stored.unwrap_or({
    objective: record.snapshot.graph.title,
    audience: "general",
    channels: ["review-only"],
    rights_owner: "unassigned",
    rights_confirmed: false,
  })
}

///|
fn current_creative(
  snapshot : @kernel.ProjectSnapshot,
  kind : @creative.ArtifactKind,
) -> @creative.CreativeArtifact? {
  let candidates = snapshot.creative_artifacts.filter(item => item.kind == kind)
  if candidates.is_empty() {
    return None
  }
  let mut current = candidates[0]
  for item in candidates {
    if item.reference.version > current.reference.version {
      current = item
    }
  }
  Some(current)
}

///|
fn creative_decision_json(
  artifact : @creative.CreativeArtifact,
  decision : @creative.CreativeDecision,
) -> Json {
  Json::object({
    "decision_id": ("decision-" +
    sha256_text(decision.to_json().stringify())[:20].to_owned()).to_json(),
    "artifact_type": artifact.kind.to_string().to_json(),
    "artifact_version": artifact.reference.version.to_json(),
    "artifact_digest": artifact.reference.digest.to_json(),
    "decision": (if decision.decision == "approved" {
      "approve"
    } else {
      decision.decision
    }).to_json(),
    "actor": decision.actor.to_json(),
    "actor_role": decision.role.to_json(),
    "decided_at": decision.decided_at.to_json(),
    "note": decision.note.to_json(),
    "digest": ("sha256:" + sha256_text(decision.to_json().stringify())).to_json(),
  })
}

///|
fn creative_artifact_json(
  snapshot : @kernel.ProjectSnapshot,
  kind : @creative.ArtifactKind,
) -> Json {
  match current_creative(snapshot, kind) {
    None => Json::null()
    Some(artifact) => {
      let decisions = snapshot.creative_decisions.filter(item => {
        item.artifact == artifact.reference
      })
      let latest = if decisions.is_empty() {
        None
      } else {
        Some(decisions[decisions.length() - 1])
      }
      let content = @json.parse(artifact.content) catch {
        _ => artifact.content.to_json()
      }
      Json::object({
        "artifact_id": artifact.reference.id.to_json(),
        "artifact_type": kind.to_string().to_json(),
        "version": artifact.reference.version.to_json(),
        "digest": artifact.reference.digest.to_json(),
        "status": match latest {
          Some(value) =>
            (if value.decision == "approved" {
              "approved"
            } else {
              value.decision
            }).to_json()
          None => "draft".to_json()
        },
        "content": content,
        "created_at": "".to_json(),
        "supersedes_digest": Json::null(),
        "latest_decision": match latest {
          Some(value) => creative_decision_json(artifact, value)
          None => Json::null()
        },
      })
    }
  }
}

///|
fn gates_json(snapshot : @kernel.ProjectSnapshot) -> Json {
  let names : Map[String, String] = {
    "G0": "Qualified scenario",
    "G1": "Rights and IP bible",
    "G2": "Script and animatic",
    "G3": "Model routing",
    "G4": "Shot quality control",
    "G5": "Master and delivery",
    "G6": "Publication authority",
    "G7": "Performance and economics",
  }
  let values : Map[String, Json] = {}
  for gate in @governance.gate_sequence() {
    let id = gate.to_string()
    let receipts = snapshot.gate_receipts.filter(item => item.gate == gate)
    values[id] = Json::object({
      "name": names.get(id).unwrap_or(id).to_json(),
      "status": (if receipts.is_empty() { "pending" } else { "passed" }).to_json(),
      "receipt": if receipts.is_empty() {
        Json::null()
      } else {
        receipts[receipts.length() - 1].to_json()
      },
    })
  }
  Json::object(values)
}

///|
fn episodes_json(graph : @project.ProjectGraph) -> Json {
  graph.episodes
  .map(episode => {
    Json::object({
      "id": episode.episode_id.to_json(),
      "title": episode.title.to_json(),
      "scenes": episode.scenes
      .map(scene => {
        Json::object({
          "id": scene.scene_id.to_json(),
          "title": scene.title.to_json(),
          "summary": scene.title.to_json(),
          "shot_ids": scene.shots.map(shot => shot.shot_id).to_json(),
        })
      })
      .to_json(),
    })
  })
  .to_json()
}

///|
fn shots_json(snapshot : @kernel.ProjectSnapshot) -> Json {
  let shots : Array[Json] = []
  for episode in snapshot.graph.episodes {
    for scene in episode.scenes {
      for shot in scene.shots {
        let attempts = snapshot.generation_attempts.filter(item => {
          item.shot_id == shot.shot_id
        })
        let latest = if attempts.is_empty() {
          None
        } else {
          Some(attempts[attempts.length() - 1])
        }
        shots.push(
          Json::object({
            "id": shot.shot_id.to_json(),
            "episode_id": episode.episode_id.to_json(),
            "scene_id": scene.scene_id.to_json(),
            "order": shot.order.to_json(),
            "duration_seconds": (shot.duration_ms.to_double() / 1000.0).to_json(),
            "prompt": (snapshot.graph.title + " — " + scene.title).to_json(),
            "subtitle": "".to_json(),
            "framing": "medium".to_json(),
            "location": shot.location_id.to_json(),
            "status": match latest {
              Some(value) =>
                (if value.status == "succeeded" {
                  "generated"
                } else {
                  value.status
                }).to_json()
              None => "planned".to_json()
            },
            "asset_id": match latest {
              Some(item) => item.output_digest.to_json()
              None => Json::null()
            },
            "provider_attempt_id": match latest {
              Some(item) => item.attempt.id.to_json()
              None => Json::null()
            },
            "qc": Json::object({
              "status": (if @governance.shot_passes_qc(
                  shot.shot_id,
                  snapshot.generation_attempts,
                  snapshot.qc_findings,
                  snapshot.qc_decisions,
                ) {
                "passed"
              } else {
                "pending"
              }).to_json(),
              "findings": snapshot.qc_findings
              .filter(item => item.shot_id == shot.shot_id)
              .to_json(),
            }),
          }),
        )
      }
    }
  }
  shots.to_json()
}

///|
fn routing_json(plan : @governance.ModelRoutingPlan?) -> Json {
  match plan {
    None => Json::null()
    Some(value) =>
      Json::object({
        "version": value.reference.version.to_json(),
        "digest": value.reference.digest.to_json(),
        "content": Json::object({
          "routes": value.routes
          .map(route => {
            Json::object({
              "route_id": route.route_id.to_json(),
              "capability": "video".to_json(),
              "asset_class": route.asset_kind.to_json(),
              "asset_ids": route.shot_ids.to_json(),
              "provider": route.provider.to_json(),
              "model": route.model.to_json(),
              "model_version": route.model_version.to_json(),
              "permitted_data_class": route.permitted_data_class.to_json(),
              "fallback": route.fallback_route_ids.to_json(),
              "retry_policy": Json::object({
                "maximum_attempts": route.retry_limit.to_json(),
                "backoff_seconds": (1).to_json(),
                "retryable_failures": ["timeout", "provider-unavailable"].to_json(),
              }),
              "unit_estimate_cny": route.cost_ceiling_cny.to_json(),
              "cost_ceiling_cny": route.cost_ceiling_cny.to_json(),
            })
          })
          .to_json(),
          "estimated_total_cny": value.routes
          .fold(init=0.0, (total, route) => total + route.cost_ceiling_cny)
          .to_json(),
          "total_ceiling_cny": value.total_cost_ceiling_cny.to_json(),
        }),
      })
  }
}

///|
fn routing_decisions_json(snapshot : @kernel.ProjectSnapshot) -> Json {
  if snapshot.routing_plan is None {
    return Json::array([])
  }
  let plan = snapshot.routing_plan.unwrap()
  let exact = snapshot.routing_decisions.filter(item => {
    item.plan == plan.reference
  })
  let producer = exact.filter(item => item.role == "producer").get(0)
  let finance = exact.filter(item => item.role == "finance").get(0)
  if producer is None && finance is None {
    return Json::array([])
  }
  [
    Json::object({
      "plan_version": plan.reference.version.to_json(),
      "plan_digest": plan.reference.digest.to_json(),
      "status": (if producer.map(item => item.decision) == Some("approved") &&
        finance.map(item => item.decision) == Some("approved") {
        "approved"
      } else {
        "pending"
      }).to_json(),
      "producer": producer.to_json(),
      "finance": finance.to_json(),
      "digest": ("sha256:" + sha256_text(exact.to_json().stringify())).to_json(),
    }),
  ].to_json()
}

///|
fn grouped_attempts_json(snapshot : @kernel.ProjectSnapshot) -> Json {
  let values : Map[String, Json] = {}
  for shot in @project.flattened_shots(snapshot.graph) {
    values[shot.shot_id] = snapshot.generation_attempts
      .filter(item => item.shot_id == shot.shot_id)
      .map(item => {
        Json::object({
          "attempt_id": item.attempt.id.to_json(),
          "version": item.attempt.version.to_json(),
          "digest": item.attempt.digest.to_json(),
          "shot_id": item.shot_id.to_json(),
          "route_id": item.route_id.to_json(),
          "output_digest": item.output_digest.to_json(),
          "asset_id": item.output_digest.to_json(),
          "status": item.status.to_json(),
          "cost_cny": item.cost_cny.to_json(),
          "duration_seconds": (item.duration_ms.to_double() / 1000.0).to_json(),
        })
      })
      .to_json()
  }
  Json::object(values)
}

///|
fn grouped_findings_json(snapshot : @kernel.ProjectSnapshot) -> Json {
  let values : Map[String, Json] = {}
  for shot in @project.flattened_shots(snapshot.graph) {
    values[shot.shot_id] = snapshot.qc_findings
      .filter(item => item.shot_id == shot.shot_id)
      .map(item => {
        Json::object({
          "finding_id": item.finding.id.to_json(),
          "version": item.finding.version.to_json(),
          "digest": item.finding.digest.to_json(),
          "shot_id": item.shot_id.to_json(),
          "attempt_digest": item.attempt_digest.to_json(),
          "dimension": qc_dimension_name(item.dimension).to_json(),
          "status": item.status.to_json(),
          "severity": item.status.to_json(),
          "evidence_digest": item.evidence_digest.to_json(),
          "message": item.note.to_json(),
          "note": item.note.to_json(),
          "recorded_at": "".to_json(),
        })
      })
      .to_json()
  }
  Json::object(values)
}

///|
fn qc_dimension_name(value : @governance.QcDimension) -> String {
  match value {
    Technical => "technical"
    Continuity => "continuity"
    Safety => "safety"
    Claims => "claims"
    Rights => "rights"
  }
}

///|
fn grouped_qc_decisions_json(snapshot : @kernel.ProjectSnapshot) -> Json {
  let values : Map[String, Json] = {}
  for shot in @project.flattened_shots(snapshot.graph) {
    let decisions : Array[Json] = []
    for decision in snapshot.qc_decisions {
      let findings = snapshot.qc_findings.filter(item => {
        item.shot_id == shot.shot_id && item.finding == decision.finding
      })
      if findings.length() == 1 {
        let finding = findings[0]
        decisions.push(
          Json::object({
            "decision_id": ("qc-decision-" +
            sha256_text(decision.to_json().stringify())[:20].to_owned()).to_json(),
            "finding_digest": finding.finding.digest.to_json(),
            "shot_id": shot.shot_id.to_json(),
            "attempt_digest": finding.attempt_digest.to_json(),
            "dimension": qc_dimension_name(finding.dimension).to_json(),
            "decision": (if decision.decision == "approved" {
              "pass"
            } else {
              decision.decision
            }).to_json(),
            "actor": decision.actor.to_json(),
            "actor_role": decision.role.to_json(),
            "decided_at": decision.decided_at.to_json(),
            "digest": ("sha256:" + sha256_text(decision.to_json().stringify())).to_json(),
          }),
        )
      }
    }
    values[shot.shot_id] = decisions.to_json()
  }
  Json::object(values)
}

///|
fn master_json(master : @governance.Master?) -> Json {
  match master {
    None => Json::null()
    Some(value) =>
      Json::object({
        "master_id": value.reference.id.to_json(),
        "version": value.reference.version.to_json(),
        "digest": value.reference.digest.to_json(),
        "sha256": value.video_digest.to_json(),
        "audio_digest": value.audio_digest.to_json(),
        "subtitle_digest": value.subtitle_digest.to_json(),
        "provenance_digest": value.provenance_digest.to_json(),
        "ai_label": value.ai_label.to_json(),
        "media": Json::object({
          "duration_seconds": value.duration_seconds.to_json(),
        }),
        "promotion": Json::object({
          "source": "editor-production-export".to_json(),
          "digest": value.reference.digest.to_json(),
        }),
      })
  }
}

///|
fn delivery_json(delivery : @governance.DeliveryPackage?) -> Json {
  match delivery {
    None => Json::null()
    Some(value) =>
      Json::object({
        "version": value.reference.version.to_json(),
        "digest": value.reference.digest.to_json(),
        "content": Json::object({
          "master_digest": value.master.digest.to_json(),
          "formats": ["mp4", "srt", "provenance-json", "rights-json"].to_json(),
          "destinations": value.destination_ids.to_json(),
          "provenance_included": true.to_json(),
          "manifest_digest": value.manifest_digest.to_json(),
          "rights_ledger_digest": value.rights_ledger_digest.to_json(),
        }),
      })
  }
}

///|
pub async fn StudioService::studio_project_projection(
  self : StudioService,
  record : ProjectRecord,
) -> Json {
  let snapshot = record.snapshot
  let experience = self.project_experience(record)
  let production = @kernel.projection(snapshot)
  let creative_history : Map[String, Json] = {}
  for
    kind in [
      @creative.Brief,
      @creative.RightsLedger,
      @creative.IpBible,
      @creative.Script,
      @creative.ClaimsLedger,
      @creative.Storyboard,
      @creative.Animatic,
    ] {
    creative_history[kind.to_string()] = snapshot.creative_artifacts
      .filter(item => item.kind == kind)
      .map(item => {
        creative_artifact_json({ ..snapshot, creative_artifacts: [item] }, kind)
      })
      .to_json()
  }
  let decisions : Array[Json] = []
  for decision in snapshot.creative_decisions {
    let artifacts = snapshot.creative_artifacts.filter(item => {
      item.reference == decision.artifact
    })
    if artifacts.length() == 1 {
      decisions.push(creative_decision_json(artifacts[0], decision))
    }
  }
  let delivery_acceptances : Array[Json] = snapshot.delivery_acceptances.map(item => {
    Json::object({
      "milestone": "delivery-package".to_json(),
      "delivery_version": item.delivery_package.version.to_json(),
      "delivery_digest": item.delivery_package.digest.to_json(),
      "decision": item.decision.to_json(),
      "actor": item.actor.to_json(),
      "decided_at": item.decided_at.to_json(),
      "digest": ("sha256:" + sha256_text(item.to_json().stringify())).to_json(),
    })
  })
  for build in self.delivery_application.list(record.project_id) {
    match self.delivery_application.acceptance(build.build_id) {
      Some(item) =>
        delivery_acceptances.push(
          Json::object({
            "milestone": "delivery-build".to_json(),
            "delivery_version": build.delivery_version.to_json(),
            "delivery_digest": build.delivery_digest.to_json(),
            "master_digest": build.master_sha256.to_json(),
            "delivery_build_digest": build.build_digest.to_json(),
            "decision": item.acceptance.decision.to_json(),
            "actor": item.acceptance.actor.to_json(),
            "decided_at": item.acceptance.decided_at.to_json(),
            "digest": item.acceptance.receipt_digest.to_json(),
          }),
        )
      None => ()
    }
  }
  let latest_performance = if snapshot.performance_reviews.is_empty() {
    None
  } else {
    Some(
      snapshot.performance_reviews[snapshot.performance_reviews.length() - 1],
    )
  }
  let project = Json::object({
    "contract": "mooncast.production-project.v2".to_json(),
    "id": record.project_id.to_json(),
    "title": snapshot.graph.title.to_json(),
    "objective": experience.objective.to_json(),
    "audience": experience.audience.to_json(),
    "channels": experience.channels.to_json(),
    "target_duration_seconds": snapshot.graph.target_duration_seconds.to_json(),
    "created_at": record.created_at.to_json(),
    "updated_at": record.updated_at.to_json(),
    "revision": snapshot.revision.to_json(),
    "stage": production.stage.to_json(),
    "current_gate": match production.current_gate {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "gates": gates_json(snapshot),
    "brief": creative_artifact_json(snapshot, @creative.Brief),
    "rights": creative_artifact_json(snapshot, @creative.RightsLedger),
    "bible": creative_artifact_json(snapshot, @creative.IpBible),
    "script": creative_artifact_json(snapshot, @creative.Script),
    "claims_ledger": creative_artifact_json(snapshot, @creative.ClaimsLedger),
    "storyboard": creative_artifact_json(snapshot, @creative.Storyboard),
    "animatic": creative_artifact_json(snapshot, @creative.Animatic),
    "creative_history": Json::object(creative_history),
    "creative_decisions": decisions.to_json(),
    "client_revision_rounds": Json::object({
      "used": (0).to_json(),
      "maximum": (2).to_json(),
    }),
    "episodes": episodes_json(snapshot.graph),
    "shots": shots_json(snapshot),
    "provider_route": Json::object({
      "id": "governed-routing-plan".to_json(),
      "provider": "configured-per-route".to_json(),
      "model": "configured-per-route".to_json(),
      "fallbacks": Json::array([]),
      "authorized": (snapshot.routing_plan is Some(_)).to_json(),
    }),
    "budget": Json::object({
      "currency": "CNY".to_json(),
      "maximum": snapshot.graph.maximum_budget_cny.to_json(),
      "reserved": snapshot.routing_plan
      .map(item => item.total_cost_ceiling_cny)
      .unwrap_or(0.0)
      .to_json(),
      "spent": snapshot.generation_attempts
      .fold(init=0.0, (total, item) => total + item.cost_cny)
      .to_json(),
    }),
    "assets": snapshot.graph.assets
    .map(item => {
      Json::object({
        "asset_id": item.asset_id.to_json(),
        "sha256": item.digest.to_json(),
        "provider": "registered-asset".to_json(),
        "model": "unknown".to_json(),
        "rights": item.rights_record_id.to_json(),
        "labels": Json::array([]),
      })
    })
    .to_json(),
    "model_routing_plan": routing_json(snapshot.routing_plan),
    "model_routing_history": Json::array([]),
    "model_routing_decisions": routing_decisions_json(snapshot),
    "generation_attempts": grouped_attempts_json(snapshot),
    "shot_qc_findings": grouped_findings_json(snapshot),
    "shot_qc_decisions": grouped_qc_decisions_json(snapshot),
    "master": master_json(snapshot.master),
    "master_lineage": match snapshot.master {
      Some(value) =>
        [
          Json::object({
            "source": "editor-production-export".to_json(),
            "master_digest": value.video_digest.to_json(),
          }),
        ].to_json()
      None => Json::array([])
    },
    "master_decisions": snapshot.master_decisions
    .map(item => {
      Json::object({
        "kind": item.kind.to_json(),
        "decision": (if item.decision == "approved" {
          "approve"
        } else {
          item.decision
        }).to_json(),
        "master_digest": item.master.digest.to_json(),
        "actor": item.actor.to_json(),
        "actor_role": item.role.to_json(),
        "decided_at": item.decided_at.to_json(),
        "digest": ("sha256:" + sha256_text(item.to_json().stringify())).to_json(),
      })
    })
    .to_json(),
    "delivery_package": delivery_json(snapshot.delivery_package),
    "delivery_milestone_acceptances": delivery_acceptances.to_json(),
    "publication_authorizations": snapshot.publication_authorizations.to_json(),
    "publication_receipts": snapshot.publication_observations.to_json(),
    "performance_reviews": snapshot.performance_reviews.to_json(),
    "outcome_handoff": self.outcome_handoff_projection(record.project_id),
    "governance_invalidations": Json::array([]),
    "reviews": Json::object({
      "qc": Json::null(),
      "editorial": Json::null(),
      "client": Json::null(),
    }),
    "delivery": Json::null(),
    "economics": Json::object({
      "provider_cost_cny": latest_performance
      .map(item => item.provider_cost_cny)
      .unwrap_or(
        snapshot.generation_attempts.fold(init=0.0, (total, item) => {
          total + item.cost_cny
        }),
      )
      .to_json(),
      "recognized_revenue_cny": latest_performance
      .map(item => item.revenue_cny)
      .unwrap_or(0.0)
      .to_json(),
      "gross_margin_cny": latest_performance
      .map(item => item.revenue_cny - item.provider_cost_cny)
      .unwrap_or(0.0)
      .to_json(),
      "founder_hours": latest_performance
      .map(item => item.founder_hours)
      .unwrap_or(0.0)
      .to_json(),
      "repeat_purchase_status": latest_performance
      .map(item => item.repeat_purchase_status)
      .unwrap_or("unreviewed")
      .to_json(),
    }),
  })
  omit_null_fields(project)
}

///|
pub async fn StudioService::creative_workspace_projection(
  self : StudioService,
  project_id : String,
  kind : @creative.ArtifactKind,
) -> Json {
  let record = self.get_project(project_id)
  let snapshot = record.snapshot
  let history = snapshot.creative_artifacts
    .filter(item => item.kind == kind)
    .map(item => {
      creative_artifact_json({ ..snapshot, creative_artifacts: [item] }, kind)
    })
  let decisions : Array[Json] = []
  for decision in snapshot.creative_decisions {
    let matches = snapshot.creative_artifacts.filter(item => {
      item.reference == decision.artifact && item.kind == kind
    })
    if matches.length() == 1 {
      decisions.push(creative_decision_json(matches[0], decision))
    }
  }
  Json::object({
    "artifact": creative_artifact_json(snapshot, kind),
    "history": history.to_json(),
    "decisions": decisions.to_json(),
    "project_revision": snapshot.revision.to_json(),
  })
}
