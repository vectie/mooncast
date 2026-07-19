///|
fn receipt_for(snapshot : ProjectSnapshot, gate : @governance.Gate) -> Bool {
  snapshot.gate_receipts.any(receipt => receipt.gate == gate)
}

///|
fn artifact(
  snapshot : ProjectSnapshot,
  kind : @creative.ArtifactKind,
) -> @creative.CreativeArtifact? {
  @creative.current_artifact(snapshot.creative_artifacts, kind)
}

///|
fn exact_creative_approval(
  snapshot : ProjectSnapshot,
  kind : @creative.ArtifactKind,
) -> Bool {
  @creative.exact_approval(
    artifact(snapshot, kind),
    snapshot.creative_decisions,
  )
}

///|
fn all_creative_bindings_current(snapshot : ProjectSnapshot) -> Bool {
  snapshot.creative_artifacts.all(item => {
    @creative.artifact_bindings_current(item, snapshot.creative_artifacts)
  })
}

///|
fn all_shots_pass(snapshot : ProjectSnapshot) -> Bool {
  let mut count = 0
  for episode in snapshot.graph.episodes {
    for scene in episode.scenes {
      for shot in scene.shots {
        count = count + 1
        if !@governance.shot_passes_qc(
            shot.shot_id,
            snapshot.generation_attempts,
            snapshot.qc_findings,
            snapshot.qc_decisions,
          ) {
          return false
        }
      }
    }
  }
  count > 0
}

///|
fn reason_if(failed : Bool, reason : String, reasons : Array[String]) -> Unit {
  if failed {
    reasons.push(reason)
  }
}

///|
pub fn gate_readiness(
  snapshot : ProjectSnapshot,
  gate : @governance.Gate,
) -> GateReadiness {
  let reasons : Array[String] = []
  let graph_validation = @project.validate_graph(snapshot.graph)
  match gate {
    G0 => {
      reason_if(!graph_validation.valid, "project_graph_invalid", reasons)
      reason_if(
        match snapshot.qualification {
          Some(value) => !value.accepted
          None => true
        },
        "qualified_paid_scenario_required",
        reasons,
      )
      reason_if(
        !exact_creative_approval(snapshot, Brief),
        "exact_brief_approval_required",
        reasons,
      )
    }
    G1 => {
      let rights = artifact(snapshot, RightsLedger)
      reason_if(
        match rights {
          Some(value) => !value.rights_cleared
          None => true
        },
        "cleared_rights_ledger_required",
        reasons,
      )
      reason_if(
        !exact_creative_approval(snapshot, RightsLedger),
        "rights_approval_required",
        reasons,
      )
      reason_if(
        !exact_creative_approval(snapshot, IpBible),
        "ip_bible_approval_required",
        reasons,
      )
    }
    G2 => {
      reason_if(
        !exact_creative_approval(snapshot, Script),
        "script_approval_required",
        reasons,
      )
      reason_if(
        !exact_creative_approval(snapshot, ClaimsLedger),
        "claims_approval_required",
        reasons,
      )
      reason_if(
        !exact_creative_approval(snapshot, Storyboard),
        "storyboard_approval_required",
        reasons,
      )
      reason_if(
        !exact_creative_approval(snapshot, Animatic),
        "animatic_approval_required",
        reasons,
      )
      reason_if(
        !all_creative_bindings_current(snapshot),
        "creative_dependency_binding_stale",
        reasons,
      )
      let storyboard = artifact(snapshot, Storyboard)
      let animatic = artifact(snapshot, Animatic)
      reason_if(
        match (storyboard, animatic) {
          (Some(board), Some(cut)) =>
            board.duration_seconds !=
            Some(snapshot.graph.target_duration_seconds) ||
            cut.duration_seconds != Some(snapshot.graph.target_duration_seconds)
          _ => true
        },
        "storyboard_animatic_duration_mismatch",
        reasons,
      )
      reason_if(
        match animatic {
          Some(value) =>
            value.expected_cost_cny.unwrap_or(-1.0) < 0.0 ||
            value.expected_cost_cny.unwrap_or(-1.0) >
            snapshot.graph.maximum_budget_cny
          None => true
        },
        "animatic_cost_outside_budget",
        reasons,
      )
    }
    G3 =>
      reason_if(
        !@governance.routing_exact_approved(
          snapshot.routing_plan,
          snapshot.routing_decisions,
          snapshot.graph.maximum_budget_cny,
        ),
        "producer_and_finance_route_approval_required",
        reasons,
      )
    G4 =>
      reason_if(
        !all_shots_pass(snapshot),
        "every_shot_must_pass_five_dimension_qc",
        reasons,
      )
    G5 => {
      reason_if(
        !@governance.master_exact_approved(
          snapshot.master,
          snapshot.master_decisions,
        ),
        "exact_master_human_and_client_approvals_required",
        reasons,
      )
      reason_if(
        !@governance.delivery_exact_accepted(
          snapshot.delivery_package,
          snapshot.master,
          snapshot.delivery_acceptances,
        ),
        "exact_delivery_package_acceptance_required",
        reasons,
      )
    }
    G6 =>
      reason_if(
        !@governance.publication_exact_authorized(
          snapshot.delivery_package,
          snapshot.publication_authorizations,
        ),
        "each_destination_requires_publication_authorization",
        reasons,
      )
    G7 =>
      reason_if(
        !@governance.performance_current(
          snapshot.delivery_package,
          snapshot.performance_reviews,
        ),
        "current_performance_and_economics_review_required",
        reasons,
      )
  }
  { gate: gate.to_string(), ready: reasons.length() == 0, reasons }
}

///|
pub fn next_gate(snapshot : ProjectSnapshot) -> @governance.Gate? {
  for gate in @governance.gate_sequence() {
    if !receipt_for(snapshot, gate) {
      return Some(gate)
    }
  }
  None
}

///|
fn current_gate(snapshot : ProjectSnapshot) -> @governance.Gate? {
  let mut current : @governance.Gate? = None
  for gate in @governance.gate_sequence() {
    if receipt_for(snapshot, gate) {
      current = Some(gate)
    } else {
      return current
    }
  }
  current
}

///|
fn stage(current : @governance.Gate?) -> String {
  match current {
    None => "draft"
    Some(G0) => "brief-ready"
    Some(G1) => "rights-ready"
    Some(G2) => "creative-approved"
    Some(G3) => "production-authorized"
    Some(G4) => "shots-qc-approved"
    Some(G5) => "master-client-accepted"
    Some(G6) => "publication-authorized"
    Some(G7) => "performance-reviewed"
  }
}

///|
pub fn projection(snapshot : ProjectSnapshot) -> ProductionProjection {
  let current = current_gate(snapshot)
  let pending = next_gate(snapshot)
  {
    current_gate: current.map(gate => gate.to_string()),
    next_gate: pending.map(gate => gate.to_string()),
    stage: stage(current),
    complete: pending is None,
    graph_validation: @project.validate_graph(snapshot.graph),
  }
}
