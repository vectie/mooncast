///|
fn[T : ToJson] ledger_optional_json(value : T?) -> Json {
  match value {
    Some(value) => value.to_json()
    None => Json::null()
  }
}

///|
/// Read-only producer evidence, scoped to an existing episode. Commercial
/// records remain project-wide: this view never allocates the same costs to
/// every episode, grants authority, or reconstructs a client access token.
pub async fn StudioService::episode_ledger(
  self : StudioService,
  project_id : String,
  episode_id : String,
) -> Json {
  let record = self.get_project(project_id)
  let snapshot = record.snapshot
  guard snapshot.graph.episodes
    .iter()
    .find_first(item => item.episode_id == episode_id)
    is Some(episode) else {
    raise NotFound(entity="episode", id=episode_id)
  }
  let blockers : Array[String] = []
  let commercial = self.commerce_application.load()
  let conversions = commercial.conversions.filter(item => {
    item.project_id == project_id
  })
  let quote = if conversions.length() == 1 {
    let matches = commercial.quotes.filter(item => {
      item.quote == conversions[0].quote &&
      item.project.project_id == project_id
    })
    if matches.length() == 1 {
      Some(matches[0])
    } else {
      None
    }
  } else {
    None
  }
  if quote is None {
    blockers.push(
      if conversions.is_empty() {
        "No exact converted quote is recorded for this project."
      } else {
        "The quote conversion cannot be joined unambiguously; reconcile the commercial record."
      },
    )
  }
  let quote_evidence = match quote {
    None => Json::null()
    Some(value) => {
      let conversion = conversions[0]
      Json::object({
        "quote": value.to_json(),
        "conversion": conversion.to_json(),
        "decisions": commercial.quote_decisions
        .filter(item => item.quote == value.quote)
        .to_json(),
        "source_lead": commercial.leads
        .filter(item => item.lead == value.source_lead)
        .to_json(),
        "capacity_at_conversion": commercial.capacity_boards
        .filter(item => {
          item.quote == value.quote && item.digest == conversion.capacity_digest
        })
        .to_json(),
        "reservation_history": commercial.reservations
        .filter(item => item.quote == value.quote)
        .to_json(),
      })
    }
  }
  let shots : Array[Json] = []
  let assets = self.asset_factory.workspace(project_id)
  let mut shots_ready = true
  for scene in episode.scenes {
    for shot in scene.shots {
      let attempts = snapshot.generation_attempts.filter(item => {
        item.shot_id == shot.shot_id
      })
      let latest = attempts.last()
      let findings = snapshot.qc_findings.filter(item => {
        item.shot_id == shot.shot_id
      })
      let decisions = snapshot.qc_decisions.filter(item => {
        findings.any(finding => finding.finding == item.finding)
      })
      let current_qc = match latest {
        Some(attempt) =>
          @governance.shot_passes_qc(
            shot.shot_id,
            [attempt],
            findings,
            decisions,
          )
        None => false
      }
      let missing_sources = shot.source_asset_ids.filter(id => {
        !snapshot.graph.assets.any(asset => asset.asset_id == id)
      })
      let source_bindings_current = match latest {
        Some(attempt) =>
          shot.source_asset_ids.all(id => {
            snapshot.graph.assets.any(asset => {
              asset.asset_id == id &&
              attempt.source_asset_digests.contains(asset.digest)
            })
          })
        None => false
      }
      if !current_qc || !missing_sources.is_empty() || !source_bindings_current {
        shots_ready = false
      }
      shots.push(
        Json::object({
          "scene_id": scene.scene_id.to_json(),
          "shot": shot.to_json(),
          "source_assets": snapshot.graph.assets
          .filter(asset => shot.source_asset_ids.contains(asset.asset_id))
          .to_json(),
          "reusable_asset_bindings": assets.shot_bindings
          .filter(binding => {
            binding.project_id == project_id && binding.shot_id == shot.shot_id
          })
          .to_json(),
          "approved_reusable_assets": assets.approved_assets
          .filter(asset => {
            assets.shot_bindings.any(binding => {
              binding.project_id == project_id &&
              binding.shot_id == shot.shot_id &&
              binding.assets.contains(asset.reference)
            })
          })
          .to_json(),
          "missing_source_asset_ids": missing_sources.to_json(),
          "source_bindings_current": source_bindings_current.to_json(),
          "attempts": attempts.to_json(),
          "latest_attempt": ledger_optional_json(latest),
          "latest_attempt_qc_passed": current_qc.to_json(),
          "qc_findings": findings.to_json(),
          "qc_decisions": decisions.to_json(),
        }),
      )
    }
  }
  let gates = @governance.gate_sequence().map(gate => {
    let readiness = @kernel.gate_readiness(snapshot, gate)
    Json::object({
      "gate": gate.to_string().to_json(),
      "current_ready": readiness.ready.to_json(),
      "reasons": readiness.reasons.to_json(),
      "receipts": snapshot.gate_receipts
      .filter(item => item.gate == gate)
      .to_json(),
    })
  })
  // Do not call editor_production_source here: its legacy fallback writes a
  // binding during reads. Only already-persisted lineage is ledger evidence.
  let source : @editor_integration.ProductionSourceBinding? = load_value(
    self.store,
    editor_production_source_key(project_id),
  )
  let source_current = match source {
    Some(value) =>
      value.project_id == project_id &&
      value.episode_id == episode_id &&
      production_source_evidence_valid(snapshot, value)
    None => false
  }
  let production_ready = [@governance.G0, G1, G2, G3, G4].all(gate => {
    @kernel.gate_readiness(snapshot, gate).ready
  })
  let promotion = self.latest_editor_promotion(project_id)
  let mut master_url : String? = None
  let mut master_available = false
  match (snapshot.master, promotion) {
    (Some(master), Some(receipt)) if source_current &&
      production_ready &&
      shots_ready &&
      normalized_digest(master.video_digest) ==
      normalized_digest(receipt.digest) =>
      try
        self.editor_export_path_for_digest(project_id, master.video_digest)
      catch {
        _ =>
          blockers.push(
            "The exact promoted master bytes are missing or do not match their digest.",
          )
      } noraise {
        _ => {
          master_available = true
          master_url = Some(
            "/api/editor/projects/" +
            project_id +
            "/exports/" +
            receipt.job_id +
            "/media",
          )
        }
      }
    (Some(_), _) =>
      blockers.push(
        "The master is retained as history; its current episode, source or approval binding needs review.",
      )
    _ => ()
  }
  let builds = self.delivery_application.list(project_id)
  let build_views : Array[Json] = []
  let current_build_ids : Array[String] = []
  for build in builds {
    let current = match (snapshot.master, snapshot.delivery_package) {
      (Some(master), Some(delivery)) =>
        master_available &&
        build.project_id == project_id &&
        delivery.master == master.reference &&
        normalized_digest(build.master_sha256) ==
        normalized_digest(master.video_digest) &&
        normalized_digest(build.delivery_digest) ==
        normalized_digest(delivery.reference.digest) &&
        build.delivery_version == delivery.reference.version &&
        build.state == "completed"
      _ => false
    }
    if current {
      current_build_ids.push(build.build_id)
    }
    let accepted = if current {
      self.delivery_application.accepted_build(build.build_id) is Some(_)
    } else {
      false
    }
    let mut download_url : String? = None
    if accepted {
      let blob = self.delivery_application.accepted_archive(build.build_id)
      match (build.archive, blob) {
        (Some(archive), Some(bytes)) if normalized_digest(archive.digest) ==
          normalized_digest(bytes.sha256) &&
          archive.bytes == bytes.bytes.length() =>
          download_url = Some(
            "/api/v2/projects/" +
            project_id +
            "/delivery-builds/" +
            build.build_id +
            "/download",
          )
        _ =>
          blockers.push(
            "Accepted package " +
            build.build_id +
            " is missing or has changed bytes; repair its artifact access.",
          )
      }
    }
    build_views.push(
      Json::object({
        "build": build.to_json(),
        "current_for_episode": current.to_json(),
        "build_acceptance_recorded": accepted.to_json(),
        "download_url": ledger_optional_json(download_url),
      }),
    )
  }
  let portals = commercial.portals.filter(item => item.project_id == project_id)
  let mut client_accepted = false
  let portal_views = portals.map(portal => {
    let current = current_build_ids.contains(portal.build_id) &&
      builds.any(build => {
        build.build_id == portal.build_id &&
        build.build_digest == portal.build_digest &&
        build.master_sha256 == portal.master_sha256 &&
        build.delivery_digest == portal.delivery_digest
      })
    let exact_acceptance = current &&
      portal.decisions.any(decision => {
        decision.portal_id == portal.portal_id &&
        decision.master_sha256 == portal.master_sha256 &&
        decision.build_digest == portal.build_digest &&
        decision.decision == "accept"
      })
    if exact_acceptance {
      client_accepted = true
    }
    Json::object({
      "portal": portal.to_json(),
      "current_for_episode": current.to_json(),
      "exact_client_acceptance_recorded": exact_acceptance.to_json(),
    })
  })
  let actuals = self.control_tower_actuals(project_id)
  let actuals = match actuals {
    Some(value) if value.project_id == project_id => Some(value)
    Some(_) => {
      blockers.push(
        "Operating actuals belong to another project; reconcile the record.",
      )
      None
    }
    None => None
  }
  let billing = commercial.billing.filter(item => item.project_id == project_id)
  let next_action = if !production_ready {
    "Review the first pending production gate and its reasons in Studio."
  } else if !shots_ready {
    "Review missing sources or QC for the latest shot attempts before making another master."
  } else if !master_available {
    "Open Editor, inspect the exact cut, and promote a verified master for this episode."
  } else if !@governance.master_internal_approved(
      snapshot.master,
      snapshot.master_decisions,
    ) {
    "Inspect the master and record the existing technical, creative and rights reviews in Delivery."
  } else if current_build_ids.is_empty() {
    "Create or resume a delivery build for this exact master in Studio Delivery."
  } else if !client_accepted {
    "Use Studio Delivery to issue or reissue the exact client review link, then await a separate client response."
  } else {
    "Review the accepted package and reconcile any unknown costs or commercial evidence."
  }
  let current_rights = current_creative(snapshot, @creative.RightsLedger)
  Json::object({
    "contract": "mooncast.episode-ledger.v1".to_json(),
    "project_id": project_id.to_json(),
    "episode_id": episode_id.to_json(),
    "title": episode.title.to_json(),
    "project_revision": snapshot.revision.to_json(),
    "commercial_revision": commercial.revision.to_json(),
    "commercial_scope": "project-wide; not allocated or summed per episode".to_json(),
    "quote_evidence": quote_evidence,
    "creative_history": snapshot.creative_artifacts.to_json(),
    "creative_decisions": snapshot.creative_decisions.to_json(),
    "production_history": record.events
    .filter(event => {
      event.gate_receipt is Some(_) ||
      event.master is Some(_) ||
      event.master_decision is Some(_) ||
      event.invalidates_from_gate is Some(_)
    })
    .to_json(),
    "current_rights": ledger_optional_json(current_rights),
    "routing_plan": ledger_optional_json(snapshot.routing_plan),
    "routing_decisions": snapshot.routing_decisions.to_json(),
    "episode": episode.to_json(),
    "shots": shots.to_json(),
    "shot_count": shots.length().to_json(),
    "gates": gates.to_json(),
    "master": ledger_optional_json(snapshot.master),
    "master_decisions": snapshot.master_decisions.to_json(),
    "production_source": ledger_optional_json(
      source.filter(value => {
        value.episode_id == episode_id && value.project_id == project_id
      }),
    ),
    "master_available": master_available.to_json(),
    "master_url": ledger_optional_json(master_url),
    "delivery_package": ledger_optional_json(snapshot.delivery_package),
    "delivery_builds": build_views.to_json(),
    "client_reviews": portal_views.to_json(),
    "client_acceptance_recorded": client_accepted.to_json(),
    "actuals": ledger_optional_json(actuals),
    "actuals_current_revision": actuals
    .map(value => value.project_revision == snapshot.revision)
    .unwrap_or(false)
    .to_json(),
    "actual_provider_cost_cny": ledger_optional_json(
      actuals.map(value => value.provider_cost_confirmed_cny).unwrap_or(None),
    ),
    "actual_labor_cost_cny": ledger_optional_json(
      actuals.map(value => value.labor_cost_cny).unwrap_or(None),
    ),
    "actual_other_cost_cny": ledger_optional_json(
      actuals.map(value => value.other_cost_cny).unwrap_or(None),
    ),
    "actual_founder_hours": ledger_optional_json(
      actuals.map(value => value.founder_hours).unwrap_or(None),
    ),
    "billing_records": billing.to_json(),
    "payment_evidence_recorded": billing
    .any(item => {
      item.state == "paid" && item.paid_at is Some(_) && item.reference != ""
    })
    .to_json(),
    "publication_records": snapshot.publication_authorizations.to_json(),
    "next_action": next_action.to_json(),
    "blockers": blockers.to_json(),
    "read_only": true.to_json(),
    "client_access_verified": false.to_json(),
    "payment_effect_performed": false.to_json(),
    "publication_authority": false.to_json(),
  })
}
