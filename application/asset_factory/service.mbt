///|
pub(all) struct PlanDecisionRequest {
  expected_plan_version : Int
  expected_plan_digest : String
  decision : String
  actor : String
  actor_role : String
  note : String
  decided_at : String
  human_confirmed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct FactoryExecutionRequest {
  expected_plan_version : Int
  expected_plan_digest : String
  actor : String
  human_confirmed : Bool
  network_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct FindingRequest {
  variant_id : String
  dimension : String
  status : String
  evidence_digest : String
  reviewer : String
  reviewer_role : String
  reviewed_at : String
  human_confirmed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AssetApprovalRequest {
  asset_id : String
  asset_version : Int
  variant_id : String
  actor : String
  actor_role : String
  approved_at : String
  human_confirmed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct AssetFactoryService {
  store : @store.AtomicStore
  execution : @execution_app.ProviderExecutionService
}

///|
pub suberror AssetFactoryApplicationError {
  FactoryInvalid(String)
  FactoryConflict(String)
  FactoryAuthorityRequired(String)
} derive(Debug)

///|
pub fn AssetFactoryService::new(
  root : String,
  execution : @execution_app.ProviderExecutionService,
) -> AssetFactoryService {
  { store: @store.AtomicStore::new(root), execution }
}

///|
fn digest_text(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn plan_key(project_id : String, version : Int) -> String {
  "asset-plan-" + project_id + "-v" + version.to_string() + ".json"
}

///|
fn decision_key(digest : String) -> String {
  "asset-plan-decision-" + digest[7:31].to_owned() + ".json"
}

///|
fn variant_key(variant_id : String) -> String {
  "asset-variant-" + variant_id + ".json"
}

///|
fn finding_key(finding_id : String) -> String {
  "asset-finding-" + finding_id + ".json"
}

///|
fn approved_key(asset_id : String, version : Int) -> String {
  "approved-asset-" + asset_id + "-v" + version.to_string() + ".json"
}

///|
fn binding_key(binding_id : String) -> String {
  "shot-asset-binding-" + binding_id + ".json"
}

///|
pub async fn AssetFactoryService::record_plan(
  self : AssetFactoryService,
  plan : @factory.AssetFactoryPlan,
  graph : @project.ProjectGraph,
  project_revision : Int,
) -> @factory.AssetFactoryPlan {
  let errors = @factory.plan_errors(plan, graph, project_revision)
  guard errors.is_empty() else {
    raise FactoryInvalid(errors.join("; "))
  }
  let key = plan_key(plan.project_id, plan.plan.version)
  match self.store.get_json(key) {
    Some(value) => {
      let prior : @factory.AssetFactoryPlan = @json.from_json(value) catch {
        _ => raise FactoryConflict("stored asset plan is corrupt")
      }
      guard prior == plan else {
        raise FactoryConflict("plan id/version already binds different evidence")
      }
      prior
    }
    None => {
      for prior in self.list_plans(plan.project_id) {
        if prior.plan.version > plan.plan.version {
          raise FactoryConflict("older asset plan cannot supersede a newer version")
        }
      }
      ignore(self.store.put_json(key, plan.to_json()))
      plan
    }
  }
}

///|
pub async fn AssetFactoryService::list_plans(
  self : AssetFactoryService,
  project_id : String,
) -> Array[@factory.AssetFactoryPlan] {
  let values : Array[@factory.AssetFactoryPlan] = []
  for key in self.store.list_keys(prefix="asset-plan-" + project_id + "-v", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let plan : @factory.AssetFactoryPlan = @json.from_json(value) catch {
          _ => continue
        }
        values.push(plan)
      }
      None => ()
    }
  }
  values
}

///|
pub async fn AssetFactoryService::current_plan(
  self : AssetFactoryService,
  project_id : String,
) -> @factory.AssetFactoryPlan? {
  let plans = self.list_plans(project_id)
  if plans.is_empty() {
    return None
  }
  let mut latest = plans[0]
  for plan in plans {
    if plan.plan.version > latest.plan.version {
      latest = plan
    }
  }
  Some(latest)
}

///|
pub async fn AssetFactoryService::decide_plan(
  self : AssetFactoryService,
  project_id : String,
  request : PlanDecisionRequest,
) -> @factory.AssetFactoryPlanDecision {
  guard self.current_plan(project_id) is Some(plan) &&
    plan.plan.version == request.expected_plan_version &&
    plan.plan.digest == request.expected_plan_digest &&
    (request.decision == "approve" || request.decision == "reject") &&
    request.actor != "" &&
    request.actor_role != "" &&
    request.decided_at != "" &&
    request.human_confirmed else {
    raise FactoryConflict("decision must bind the exact plan and named human")
  }
  let digest = digest_text(
    plan.plan.digest +
    ":" +
    request.decision +
    ":" +
    request.actor +
    ":" +
    request.actor_role +
    ":" +
    request.note +
    ":" +
    request.decided_at,
  )
  let decision : @factory.AssetFactoryPlanDecision = {
    contract: "mooncast.asset-factory-plan-decision.v1",
    plan: plan.plan,
    decision: request.decision,
    actor: request.actor,
    actor_role: request.actor_role,
    note: request.note,
    decided_at: request.decided_at,
    human_confirmed: true,
    decision_digest: digest,
    provider_execution_authority: false,
    publication_authority: false,
  }
  ignore(self.store.put_json(decision_key(digest), decision.to_json()))
  decision
}

///|
async fn AssetFactoryService::plan_approved(
  self : AssetFactoryService,
  plan : @factory.AssetFactoryPlan,
) -> Bool {
  let matches = self.list_plan_decisions().filter(value => value.plan == plan.plan)
  if matches.is_empty() {
    return false
  }
  let mut latest = matches[0]
  for item in matches {
    if item.decided_at > latest.decided_at {
      latest = item
    }
  }
  latest.decision == "approve"
}

///|
pub async fn AssetFactoryService::list_plan_decisions(
  self : AssetFactoryService,
) -> Array[@factory.AssetFactoryPlanDecision] {
  let values : Array[@factory.AssetFactoryPlanDecision] = []
  for key in self.store.list_keys(prefix="asset-plan-decision-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => values.push(@json.from_json(value))
      None => ()
    }
  }
  values
}

///|
pub async fn AssetFactoryService::authorize_variants(
  self : AssetFactoryService,
  project_id : String,
  request : FactoryExecutionRequest,
) -> Array[@factory.AssetGenerationVariant] {
  guard self.current_plan(project_id) is Some(plan) &&
    plan.plan.version == request.expected_plan_version &&
    plan.plan.digest == request.expected_plan_digest &&
    self.plan_approved(plan) &&
    request.actor != "" &&
    request.human_confirmed &&
    request.network_authority else {
    raise FactoryAuthorityRequired(
      "exact approved plan and explicit provider authority are required",
    )
  }
  let variants : Array[@factory.AssetGenerationVariant] = []
  for spec in plan.specs {
    for variant = 1; variant <= spec.variant_limit; variant = variant + 1 {
      let variant_id = spec.asset_id + "-v" + spec.asset_version.to_string() + "-variant-" + variant.to_string()
      match self.store.get_json(variant_key(variant_id)) {
        Some(value) => {
          variants.push(@json.from_json(value))
          continue
        }
        None => ()
      }
      let provider = self.execution.authorize_asset_from_catalog(
        {
          contract: "mooncast.asset-provider-request.v1",
          request_id: plan.plan.id + ":" + variant_id,
          project_id,
          project_revision: plan.project_revision,
          asset_id: spec.asset_id,
          asset_version: spec.asset_version,
          variant,
          kind: spec.kind,
          capability: spec.capability,
          intent_ref: spec.intent.provenance_ref,
          prompt_digest: spec.prompt_digest,
          source_asset_refs: spec.source_asset_refs,
          rights_refs: spec.rights_refs,
          continuity_key: spec.continuity_key,
          adapter_id: spec.provider_adapter_id,
          provider: spec.provider,
          model: spec.model,
          permitted_data_class: spec.permitted_data_class,
          cost_ceiling_cny: spec.cost_ceiling_cny,
          retry_limit: spec.retry_limit,
          parameters: {},
          publication_authority: false,
        },
        request.actor,
        true,
      )
      let item : @factory.AssetGenerationVariant = {
        contract: "mooncast.asset-generation-variant.v1",
        variant_id,
        plan: plan.plan,
        asset_id: spec.asset_id,
        asset_version: spec.asset_version,
        variant,
        provider_job_id: provider.job.job_id,
        provider_artifact_id: None,
        output_digest: None,
        modality: spec.capability,
        cost_cny: 0.0,
        state: provider.job.state,
        evidence_refs: [plan.plan.digest, spec.intent.source_digest, spec.prompt_digest, ..spec.rights_refs],
        updated_at: provider.updated_at,
        network_effect_performed: false,
        publication_authority: false,
        immutable: false,
      }
      ignore(self.store.put_json(variant_key(variant_id), item.to_json()))
      variants.push(item)
    }
  }
  variants
}

///|
async fn AssetFactoryService::refresh_variant(
  self : AssetFactoryService,
  value : @factory.AssetGenerationVariant,
) -> @factory.AssetGenerationVariant {
  match self.execution.load_job(value.provider_job_id) {
    None => value
    Some(record) => {
      let artifact = record.job.artifacts.get(0)
      let refreshed = {
        ..value,
        provider_artifact_id: artifact.map(item => item.artifact_id),
        output_digest: artifact.map(item => item.artifact_digest),
        cost_cny: record.job.spent_cny,
        state: record.job.state,
        updated_at: record.updated_at,
        network_effect_performed: record.host_effect_receipts.any(item => {
          item.network_effect_performed
        }),
        immutable: record.job.state == "completed",
      }
      ignore(self.store.put_json(variant_key(value.variant_id), refreshed.to_json()))
      refreshed
    }
  }
}

///|
pub async fn AssetFactoryService::run_pending(
  self : AssetFactoryService,
  project_id : String,
  request : FactoryExecutionRequest,
) -> Array[@factory.AssetGenerationVariant] {
  let values = self.authorize_variants(project_id, request)
  let completed : Array[@factory.AssetGenerationVariant] = []
  for value in values {
    let current = self.refresh_variant(value)
    let executed = if current.state == "authorized" ||
      current.state == "retryable_failure" ||
      current.state == "timed_out" {
      ignore(self.execution.execute(current.provider_job_id))
      self.refresh_variant(current)
    } else {
      current
    }
    completed.push(executed)
  }
  completed
}

///|
pub async fn AssetFactoryService::record_finding(
  self : AssetFactoryService,
  request : FindingRequest,
) -> @factory.AssetQcFinding {
  guard @factory.required_qc_dimensions().contains(request.dimension) &&
    (request.status == "pass" || request.status == "fail") &&
    request.evidence_digest != "" &&
    request.reviewer != "" &&
    request.reviewer_role != "" &&
    request.reviewed_at != "" &&
    request.human_confirmed &&
    self.variant(request.variant_id) is Some(variant) &&
    variant.state == "completed" else {
    raise FactoryInvalid("QC must bind a completed variant and named reviewer")
  }
  let finding_id = "asset-qc-" + digest_text(
    request.variant_id + ":" + request.dimension + ":" + request.evidence_digest + ":" + request.reviewer + ":" + request.reviewed_at,
  )[7:31].to_owned()
  let finding : @factory.AssetQcFinding = {
    contract: "mooncast.asset-qc-finding.v1",
    finding_id,
    variant_id: request.variant_id,
    dimension: request.dimension,
    status: request.status,
    evidence_digest: request.evidence_digest,
    reviewer: request.reviewer,
    reviewer_role: request.reviewer_role,
    reviewed_at: request.reviewed_at,
    human_confirmed: true,
    immutable: true,
  }
  ignore(self.store.put_json(finding_key(finding_id), finding.to_json()))
  finding
}

///|
pub async fn AssetFactoryService::variant(
  self : AssetFactoryService,
  variant_id : String,
) -> @factory.AssetGenerationVariant? {
  match self.store.get_json(variant_key(variant_id)) {
    Some(value) => Some(@json.from_json(value))
    None => None
  }
}

///|
pub async fn AssetFactoryService::list_variants(
  self : AssetFactoryService,
) -> Array[@factory.AssetGenerationVariant] {
  let values : Array[@factory.AssetGenerationVariant] = []
  for key in self.store.list_keys(prefix="asset-variant-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => values.push(self.refresh_variant(@json.from_json(value)))
      None => ()
    }
  }
  values
}

///|
pub async fn AssetFactoryService::list_findings(
  self : AssetFactoryService,
) -> Array[@factory.AssetQcFinding] {
  let values : Array[@factory.AssetQcFinding] = []
  for key in self.store.list_keys(prefix="asset-finding-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => values.push(@json.from_json(value))
      None => ()
    }
  }
  values
}

///|
pub async fn AssetFactoryService::approve_asset(
  self : AssetFactoryService,
  request : AssetApprovalRequest,
) -> @factory.ApprovedReusableAsset {
  guard request.actor != "" &&
    request.actor_role != "" &&
    request.approved_at != "" &&
    request.human_confirmed &&
    self.variant(request.variant_id) is Some(variant) &&
    variant.asset_id == request.asset_id &&
    variant.asset_version == request.asset_version &&
    variant.state == "completed" &&
    variant.provider_artifact_id is Some(provider_artifact_id) &&
    variant.output_digest is Some(output_digest) &&
    @factory.variant_passes_qc(request.variant_id, self.list_findings()) else {
    raise FactoryInvalid("approval requires completed output and five passing QC dimensions")
  }
  guard self.current_plan_from_ref(variant.plan) is Some(plan) &&
    plan.specs.iter().find_first(spec => {
      spec.asset_id == request.asset_id && spec.asset_version == request.asset_version
    }) is Some(spec) else {
    raise FactoryConflict("asset spec changed before approval")
  }
  let findings = self.list_findings().filter(value => value.variant_id == request.variant_id)
  let approval_digest = digest_text(
    output_digest + ":" + request.actor + ":" + request.actor_role + ":" + request.approved_at + ":" + findings.map(item => item.finding_id).join("|"),
  )
  let approved : @factory.ApprovedReusableAsset = {
    contract: "mooncast.approved-reusable-asset.v1",
    reference: {
      asset_id: request.asset_id,
      kind: spec.kind,
      version: request.asset_version,
      digest: output_digest,
      uri: "provider-artifact:" + provider_artifact_id,
      rights_record_id: digest_text(spec.rights_refs.join("|")),
      immutable: true,
    },
    plan: plan.plan,
    spec_version: request.asset_version,
    variant_id: request.variant_id,
    provider_job_id: variant.provider_job_id,
    provider_artifact_id,
    output_digest,
    modality: variant.modality,
    continuity_key: spec.continuity_key,
    intent: spec.intent,
    rights_refs: spec.rights_refs,
    qc_finding_ids: findings.map(item => item.finding_id),
    approval_actor: request.actor,
    approval_role: request.actor_role,
    approved_at: request.approved_at,
    approval_digest,
    publication_authority: false,
    immutable: true,
  }
  let key = approved_key(request.asset_id, request.asset_version)
  match self.store.get_json(key) {
    Some(value) => {
      let prior : @factory.ApprovedReusableAsset = @json.from_json(value)
      guard prior == approved else {
        raise FactoryConflict("asset version already has a different approval")
      }
      prior
    }
    None => {
      ignore(self.store.put_json(key, approved.to_json()))
      approved
    }
  }
}

///|
async fn AssetFactoryService::current_plan_from_ref(
  self : AssetFactoryService,
  reference : @project.VersionRef,
) -> @factory.AssetFactoryPlan? {
  for key in self.store.list_keys(prefix="asset-plan-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let plan : @factory.AssetFactoryPlan = @json.from_json(value)
        if plan.plan == reference {
          return Some(plan)
        }
      }
      None => ()
    }
  }
  None
}

///|
pub async fn AssetFactoryService::list_approved_assets(
  self : AssetFactoryService,
) -> Array[@factory.ApprovedReusableAsset] {
  let values : Array[@factory.ApprovedReusableAsset] = []
  for key in self.store.list_keys(prefix="approved-asset-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => values.push(@json.from_json(value))
      None => ()
    }
  }
  values
}

///|
pub async fn AssetFactoryService::bind_approved_assets(
  self : AssetFactoryService,
  project_id : String,
  project_revision : Int,
  shot_ids : ArrayView[String],
  bound_at : String,
) -> Array[@factory.ShotAssetBinding] {
  guard self.current_plan(project_id) is Some(plan) &&
    plan.project_revision == project_revision else {
    raise FactoryConflict("shot bindings require the exact current asset plan")
  }
  let approved = self.list_approved_assets()
  let bindings : Array[@factory.ShotAssetBinding] = []
  for shot_id in shot_ids {
    let specs = plan.specs.filter(spec => spec.dependent_shot_ids.contains(shot_id))
    if specs.is_empty() {
      continue
    }
    let assets : Array[@project.Asset] = []
    let approvals : Array[String] = []
    for spec in specs {
      guard approved.iter().find_first(value => {
          value.reference.asset_id == spec.asset_id &&
          value.reference.version == spec.asset_version &&
          value.plan == plan.plan
        }) is Some(value) else {
        raise FactoryConflict("every dependent asset must be approved before shot binding")
      }
      assets.push(value.reference)
      approvals.push(value.approval_digest)
    }
    let binding_id = digest_text(
      project_id + ":" + project_revision.to_string() + ":" + shot_id + ":" + approvals.join("|"),
    )[7:31].to_owned()
    let binding : @factory.ShotAssetBinding = {
      contract: "mooncast.shot-asset-binding.v1",
      binding_id,
      project_id,
      project_revision,
      shot_id,
      assets,
      approval_digests: approvals,
      bound_at,
      immutable: true,
      publication_authority: false,
    }
    ignore(self.store.put_json(binding_key(binding_id), binding.to_json()))
    bindings.push(binding)
  }
  bindings
}

///|
pub async fn AssetFactoryService::list_bindings(
  self : AssetFactoryService,
) -> Array[@factory.ShotAssetBinding] {
  let values : Array[@factory.ShotAssetBinding] = []
  for key in self.store.list_keys(prefix="shot-asset-binding-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => values.push(@json.from_json(value))
      None => ()
    }
  }
  values
}

///|
pub async fn AssetFactoryService::shot_assets(
  self : AssetFactoryService,
  project_id : String,
  project_revision : Int,
  shot_id : String,
) -> Array[@project.Asset]? {
  let matches = self.list_bindings().filter(value => {
    value.project_id == project_id &&
    value.project_revision == project_revision &&
    value.shot_id == shot_id
  })
  if matches.length() == 1 { Some(matches[0].assets) } else { None }
}

///|
pub async fn AssetFactoryService::workspace(
  self : AssetFactoryService,
  project_id : String,
) -> @factory.AssetFactoryWorkspace {
  let project_plans = self.list_plans(project_id)
  let variants = self.list_variants().filter(value => {
    project_plans.any(plan => plan.plan == value.plan)
  })
  let plan_decisions = self.list_plan_decisions().filter(value => {
    project_plans.any(plan => plan.plan == value.plan)
  })
  let approved_assets = self.list_approved_assets().filter(value => {
    project_plans.any(plan => plan.plan == value.plan)
  })
  {
    contract: "mooncast.asset-factory-workspace.v1",
    plans: project_plans,
    plan_decisions,
    variants,
    findings: self.list_findings(),
    approved_assets,
    shot_bindings: self.list_bindings().filter(value => value.project_id == project_id),
    total_spent_cny: variants.fold(init=0.0, (sum, value) => sum + value.cost_cny),
    publication_authority: false,
    provider_execution_authority: false,
  }
}
