///|
struct ProviderJobsProjection {
  jobs : Array[@execution.ProviderExecutionJob]
  publication_authority : Bool
} derive(ToJson)

///|
struct PortalsProjection {
  portals : Array[@commerce.ClientPortal]
  publication_authority : Bool
} derive(ToJson)

///|
struct BillingProjection {
  entries : Array[@commerce.MilestoneBillingEntry]
  payment_effect_performed : Bool
} derive(ToJson)

///|
struct RoutedActionRequest {
  expected_execution_revision : Int
  expected_execution_digest : String?
  actor_id : String
} derive(FromJson)

///|
struct RoutedCreateRequest {
  expected_project_revision : Int
  expected_routing_plan_version : Int
  expected_routing_plan_digest : String
  actor_id : String
  network_authority : Bool
  publication_authority : Bool
} derive(FromJson)

///|
struct RoutedExecutionsProjection {
  executions : Array[Json]
  publication_authority : Bool
} derive(ToJson)

///|
struct RoutedActionProjection {
  execution : Json
  job : Json
  publication_authority : Bool
} derive(ToJson)

///|
struct ClientProjectEpisodeProjection {
  episode_id : String
  title : String
  scene_count : Int
} derive(ToJson)

///|
struct ClientProjectProjection {
  project_id : String
  title : String
  objective : String
  target_duration_seconds : Int
  episodes : Array[ClientProjectEpisodeProjection]
} derive(ToJson)

///|
struct ClientBindingProjection {
  master_sha256 : String
  delivery_digest : String
  build_id : String
  build_digest : String
} derive(ToJson)

///|
struct ClientRevisionPolicyProjection {
  maximum : Int
  used : Int
  remaining : Int
} derive(ToJson)

///|
struct ClientArtifactProjection {
  name : String
  kind : String
  size_bytes : Int
  sha256 : String
} derive(ToJson)

///|
struct ClientDeliveryProjection {
  accepted : Bool
  download_url : String?
  archive_name : String
  artifacts : Array[ClientArtifactProjection]
} derive(ToJson)

///|
struct ClientWorkspaceProjection {
  contract : String
  portal : @commerce.ClientPortal
  brand : @commerce.ClientBrand
  project : ClientProjectProjection
  binding : ClientBindingProjection
  annotations : Array[@commerce.ClientAnnotation]
  decisions : Array[@commerce.ClientDecisionReceipt]
  revision_policy : ClientRevisionPolicyProjection
  delivery : ClientDeliveryProjection
  review_master_url : String
  provider_data_included : Bool
  publication_authority : Bool
} derive(ToJson)

///|
struct ClientAnnotationInput {
  expected_master_sha256 : String
  expected_build_digest : String
  timecode_seconds : Double
  author : String
  body : String
} derive(FromJson)

///|
struct ClientDecisionInput {
  expected_master_sha256 : String
  expected_build_digest : String
  human_confirmed : Bool
  actor : String
  decision : String
  note : String
} derive(FromJson)

///|
struct EditorHandoffRequestInput {
  candidate_id : String?
  candidate_version : String?
  workflow_ref : @handoff.RecordRef
  ability_ref : @handoff.RecordRef
  intake_authority_ref : @handoff.RecordRef
  episode_id : String
  submitted_at : String?
} derive(FromJson)

///|
struct ClientPortalCreateInput {
  expected_project_revision : Int
  expected_master_sha256 : String
  build_id : String
  expected_build_digest : String
  expected_build_record_digest : String
  client_name : String
  brand_name : String
  brand_accent : String
  expires_at : String
  human_confirmed : Bool
  actor : String
  actor_role : String
} derive(FromJson)

///|
struct ClientPortalCreateProjection {
  portal : @commerce.ClientPortal
  client_url : String
  raw_token_returned_once : Bool
  external_effect_performed : Bool
  publication_authority : Bool
} derive(ToJson)

///|
struct ClientPortalControlInput {
  expected_portal_revision : Int
  expected_portal_digest : String
  human_confirmed : Bool
  actor : String
  actor_role : String
} derive(FromJson)

///|
struct BillingCreateInput {
  expected_project_revision : Int
  kind : String
  state : String
  currency : String
  amount : Double
  due_at : String?
  reference : String
  human_confirmed : Bool
  actor : String
  actor_role : String
} derive(FromJson)

///|
struct BillingTransitionInput {
  expected_billing_revision : Int
  expected_billing_digest : String
  state : String
  human_confirmed : Bool
  actor : String
  actor_role : String
  reference : String
} derive(FromJson)

///|
struct DeliveryVariantInput {
  variant_id : String
  orientation : String
  width : Int
  height : Int
  policy : String
} derive(ToJson, FromJson)

///|
struct DeliveryCutInput {
  cut_id : String
  channel : String
  source_variant : String
  in_seconds : Double
  out_seconds : Double
} derive(ToJson, FromJson)

///|
struct DeliveryCoverInput {
  cover_id : String
  source_variant : String
  timestamp_seconds : Double
  format : String
} derive(ToJson, FromJson)

///|
struct DeliveryProfileInput {
  contract : String
  version : Int
  include_source_master : Bool
  variants : Array[DeliveryVariantInput]
  cuts : Array[DeliveryCutInput]
  covers : Array[DeliveryCoverInput]
  include_subtitles : Bool
  include_metadata : Bool
  include_provenance_rights_ai_manifest : Bool
} derive(ToJson, FromJson)

///|
struct DeliveryCreateInput {
  expected_project_revision : Int
  expected_master_sha256 : String
  expected_delivery_version : Int
  expected_delivery_digest : String
  profile : DeliveryProfileInput
} derive(FromJson)

///|
struct DeliveryActionInput {
  expected_build_revision : Int
  expected_record_digest : String
  actor : String
} derive(FromJson)

///|
struct DeliveryAcceptanceInput {
  expected_project_revision : Int
  expected_build_digest : String
  expected_build_record_digest : String
  human_confirmed : Bool
  actor : String
  actor_role : String
  decision : String
  note : String
} derive(FromJson)

///|
struct DeliveryArtifactProjection {
  artifact_id : String
  kind : String
  name : String
  media_type : String
  size_bytes : Int
  sha256 : String
} derive(ToJson)

///|
struct DeliveryBuildProjection {
  contract : String
  build_id : String
  build_digest : String
  project_id : String
  project_revision : Int
  master_sha256 : String
  delivery_version : Int
  delivery_digest : String
  profile_version : Int
  profile_digest : String
  state : String
  revision : Int
  attempt_count : Int
  recovery_count : Int
  artifacts : Array[DeliveryArtifactProjection]
  archive : DeliveryArtifactProjection?
  download_url : String?
  economics_receipt : String?
  last_error : String?
  created_at : String
  updated_at : String
  publication_authority : Bool
  record_digest : String
} derive(ToJson)

///|
struct DeliveryAcceptanceProjection {
  project : Json
  build : DeliveryBuildProjection
  acceptance : @execution.DeliveryBuildAcceptance
  publication_authority : Bool
} derive(ToJson)

///|
struct DeliveryBuildsProjection {
  builds : Array[DeliveryBuildProjection]
  publication_authority : Bool
} derive(ToJson)

///|
async fn StudioService::client_binding(
  self : StudioService,
  token : String,
) -> (@commerce.ClientPortal, @execution_app.DeliveryFactoryRecord) {
  let portal = self.commerce_application.client_portal_for_token(
    token,
    now_string(),
  )
  guard self.delivery_application.load(portal.build_id) is Some(build) else {
    fail("client delivery build is missing")
  }
  (portal, build)
}

///|
async fn StudioService::serve_client_master(
  self : StudioService,
  token : String,
  request : @host_http.Request,
) -> @host_http.Response {
  let (portal, build) = self.client_binding(token)
  guard portal.scopes.any(scope => scope == "master-read") else {
    return api_error(
      403, "client_master_denied", "client portal does not grant master review",
    )
  }
  let path = build.request.master_path
  guard @fs.exists(path) else {
    return api_error(
      404, "client_master_missing", "accepted review master is missing",
    )
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size <= 1073741824L else {
    return api_error(
      413, "client_master_too_large", "review master exceeds the native read limit",
    )
  }
  let content = file.read_exactly_at(size.to_int(), position=0)
  let digest = "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(content))
  guard digest == normalized_digest(portal.master_sha256) else {
    return api_error(
      409, "client_master_integrity_failed", "review master differs from the accepted portal binding",
    )
  }
  let range = request.headers.get("range")
  let if_none_match = request.headers.get("if-none-match")
  let response = @host_http.static_response(
    digest,
    content,
    range?,
    if_none_match?,
  )
  response.headers["Content-Type"] = "video/mp4"
  response
}

///|
async fn StudioService::client_workspace(
  self : StudioService,
  token : String,
) -> ClientWorkspaceProjection {
  let (portal, record) = self.client_binding(token)
  let canonical = self.get_project(portal.project_id)
  let project = canonical.snapshot.graph
  let accepted = portal.decisions.any(decision => decision.decision == "accept")
  let used = portal.decisions
    .filter(decision => decision.decision == "request-revision")
    .length()
  let artifacts = record.build.artifacts.map(artifact => ClientArtifactProjection::{
    name: artifact.filename,
    kind: artifact.kind,
    size_bytes: artifact.bytes,
    sha256: artifact.digest,
  })
  {
    contract: "mooncast.client-workspace-projection.v1",
    portal,
    brand: portal.brand,
    project: {
      project_id: project.project_id,
      title: project.title,
      objective: project.title,
      target_duration_seconds: project.target_duration_seconds,
      episodes: project.episodes.map(episode => {
        episode_id: episode.episode_id,
        title: episode.title,
        scene_count: episode.scenes.length(),
      }),
    },
    binding: {
      master_sha256: portal.master_sha256,
      delivery_digest: portal.delivery_digest,
      build_id: portal.build_id,
      build_digest: portal.build_digest,
    },
    annotations: portal.annotations,
    decisions: portal.decisions,
    revision_policy: { maximum: 2, used, remaining: 2 - used },
    delivery: {
      accepted,
      download_url: if accepted {
        Some("download")
      } else {
        None
      },
      archive_name: match record.build.archive {
        Some(value) => value.filename
        None => "mooncast-delivery.zip"
      },
      artifacts,
    },
    review_master_url: "master",
    provider_data_included: false,
    publication_authority: false,
  }
}

///|
async fn StudioService::record_client_annotation_from_ui(
  self : StudioService,
  token : String,
  input : ClientAnnotationInput,
) -> @commerce.ClientAnnotation {
  let (portal, _) = self.client_binding(token)
  guard normalized_digest(input.expected_master_sha256) ==
    normalized_digest(portal.master_sha256) &&
    normalized_digest(input.expected_build_digest) ==
    normalized_digest(portal.build_digest) else {
    fail("client annotation is stale")
  }
  let created_at = now_string()
  let annotation_id = @runtime.new_id(prefix="annotation")
  let digest = "sha256:" +
    sha256_text(
      annotation_id +
      ":" +
      portal.portal_id +
      ":" +
      input.timecode_seconds.to_string() +
      ":" +
      input.author +
      ":" +
      input.body +
      ":" +
      created_at,
    )
  let annotation : @commerce.ClientAnnotation = {
    contract: "mooncast.client-annotation.v1",
    annotation_id,
    portal_id: portal.portal_id,
    master_sha256: portal.master_sha256,
    build_digest: portal.build_digest,
    timecode_seconds: input.timecode_seconds,
    body: input.body,
    author: input.author,
    created_at,
    digest,
  }
  let project = self.get_project(portal.project_id)
  self.commerce_application.annotate(
    token,
    created_at,
    annotation,
    project.snapshot.graph.target_duration_seconds.to_double(),
    digest,
  )
}

///|
async fn StudioService::record_client_decision_from_ui(
  self : StudioService,
  token : String,
  input : ClientDecisionInput,
) -> @commerce.ClientDecisionReceipt {
  guard input.human_confirmed else {
    fail("client decision needs explicit human confirmation")
  }
  let (portal, build_record) = self.client_binding(token)
  guard normalized_digest(input.expected_master_sha256) ==
    normalized_digest(portal.master_sha256) &&
    normalized_digest(input.expected_build_digest) ==
    normalized_digest(portal.build_digest) else {
    fail("client decision is stale")
  }
  let canonical = self.get_project(portal.project_id)
  let decided_at = now_string()
  let governance_digest = "sha256:" +
    sha256_text(input.actor + ":" + input.note + ":" + decided_at)
  let digest = "sha256:" +
    sha256_text(
      portal.portal_id +
      ":" +
      input.decision +
      ":" +
      portal.build_digest +
      ":" +
      governance_digest,
    )
  let decision : @commerce.ClientDecisionReceipt = {
    contract: "mooncast.client-decision-receipt.v1",
    portal_id: portal.portal_id,
    decision: input.decision,
    master_sha256: portal.master_sha256,
    build_digest: portal.build_digest,
    governance_receipt_digest: governance_digest,
    project_revision: canonical.snapshot.revision,
    decided_at,
    digest,
  }
  let receipt = self.commerce_application.record_client_decision(
    token, decided_at, decision, digest,
  )
  if input.decision == "accept" {
    let before_master = self.get_project(portal.project_id)
    guard before_master.snapshot.master is Some(master) &&
      before_master.snapshot.delivery_package is Some(_) else {
      fail(
        "client acceptance requires the exact canonical master and delivery intent",
      )
    }
    if !before_master.snapshot.master_decisions.any(item => {
        item.master == master.reference &&
        item.kind == "client" &&
        item.decision == "approved"
      }) {
      ignore(
        self.record_master_decision_feature(portal.project_id, "client", {
          expected_project_revision: before_master.snapshot.revision,
          expected_master_version: master.reference.version,
          expected_master_digest: master.reference.digest,
          human_confirmed: true,
          actor: input.actor,
          actor_role: "client",
          decision: "approve",
          note: input.note,
        }),
      )
    }
    let before_delivery = self.get_project(portal.project_id)
    guard before_delivery.snapshot.delivery_package is Some(delivery) else {
      fail("client acceptance requires the exact delivery intent")
    }
    if !before_delivery.snapshot.delivery_acceptances.any(item => {
        item.delivery_package == delivery.reference &&
        item.decision == "accepted"
      }) {
      ignore(
        self.record_delivery_milestone_feature(portal.project_id, {
          expected_project_revision: before_delivery.snapshot.revision,
          expected_delivery_version: delivery.reference.version,
          expected_delivery_digest: delivery.reference.digest,
          milestone: "client-exact-build-acceptance",
          human_confirmed: true,
          actor: input.actor,
          actor_role: "client",
          decision: "accept",
          note: input.note,
        }),
      )
    }
    let build_acceptance : @execution.DeliveryBuildAcceptance = {
      contract: "mooncast.delivery-build-acceptance.v1",
      build_digest: build_record.build.build_digest,
      build_record_digest: build_record.build.record_digest,
      decision: "accept",
      actor: input.actor,
      actor_role: "client",
      note: input.note,
      project_revision: build_record.build.project_revision,
      decided_at,
      receipt_digest: digest,
    }
    ignore(
      self.delivery_application.record_acceptance(
        build_record.build.build_id,
        build_acceptance,
      ),
    )
    ignore(
      self.advance_ready_gates(
        portal.project_id,
        input.actor,
        "client",
        receipt.digest,
      ),
    )
  }
  receipt
}

///|
async fn StudioService::submit_editor_handoff_request(
  self : StudioService,
  project_id : String,
  job_id : String,
  input : EditorHandoffRequestInput,
) -> @handoff_app.ImmutablePutResult {
  let canonical = self.get_project(project_id)
  let export_job = self.get_editor_job(project_id, job_id)
  guard self.editor_production_source(project_id) is Some(source) &&
    production_source_evidence_valid(canonical.snapshot, source) &&
    input.episode_id == source.episode_id &&
    input.intake_authority_ref.record_id ==
    project_id + "-production-source-r" + source.production_revision.to_string() &&
    normalized_digest(input.intake_authority_ref.record_digest) ==
    normalized_digest(source.binding_digest) &&
    input.intake_authority_ref.provenance_ref == source.provenance_ref else {
    fail(
      "MoonFlow handoff requires the exact immutable production source binding",
    )
  }
  guard export_job.job.state == "succeeded" &&
    export_job.export_receipt is Some(receipt) else {
    fail("only a completed production export can enter MoonFlow")
  }
  let duration = canonical.snapshot.graph.target_duration_seconds
  guard duration >= 180 && duration <= 480 else {
    fail("MoonFlow v1 accepts complete 3-8 minute episodes")
  }
  guard gate_recorded(canonical.snapshot, "G5") &&
    @governance.master_exact_approved(
      canonical.snapshot.master,
      canonical.snapshot.master_decisions,
    ) &&
    @governance.delivery_exact_accepted(
      canonical.snapshot.delivery_package,
      canonical.snapshot.master,
      canonical.snapshot.delivery_acceptances,
    ) &&
    canonical.snapshot.master is Some(master) &&
    canonical.snapshot.delivery_package is Some(delivery) &&
    normalized_digest(master.video_digest) == normalized_digest(receipt.digest) else {
    fail(
      "MoonFlow handoff requires the exact G5 client-accepted master and delivery intent",
    )
  }
  let accepted_builds = self.delivery_application
    .list(project_id)
    .filter(build => {
      build.state == "completed" &&
      normalized_digest(build.master_sha256) ==
      normalized_digest(master.video_digest) &&
      build.delivery_version == delivery.reference.version &&
      normalized_digest(build.delivery_digest) ==
      normalized_digest(delivery.reference.digest)
    })
  let mut real_client_acceptance = false
  let commerce = self.commerce_application.load()
  for build in accepted_builds {
    if self.delivery_application.acceptance(build.build_id) is Some(acceptance) &&
      acceptance.acceptance.decision == "accept" &&
      acceptance.acceptance.actor_role == "client" &&
      commerce.portals.any(portal => {
        portal.project_id == project_id &&
        portal.build_id == build.build_id &&
        portal.decisions.any(decision => decision.decision == "accept")
      }) {
      real_client_acceptance = true
    }
  }
  guard real_client_acceptance else {
    fail(
      "MoonFlow handoff requires a completed build accepted in the real client portal",
    )
  }
  let candidate_id = input.candidate_id.unwrap_or(
    "candidate-" + sha256_text(project_id + ":" + job_id)[:20].to_owned(),
  )
  let record_digest = "sha256:" +
    sha256_text(candidate_id + ":" + receipt.digest + ":" + receipt.plan_digest)
  let prepared_at = input.submitted_at.unwrap_or(now_string())
  let evidence : @handoff.FinalDeliverableEvidence = {
    contract: "mooncast.final-deliverable-evidence.v1",
    record: {
      record_id: candidate_id,
      record_version: input.candidate_version.unwrap_or("1"),
      record_digest,
      provenance_ref: "/api/editor/projects/" +
      project_id +
      "/exports/" +
      job_id,
    },
    project_id,
    episode_id: input.episode_id,
    export_job_id: job_id,
    editor_output_digest: receipt.digest,
    render_plan_digest: receipt.plan_digest,
    lineage_evidence_digest: "sha256:" +
    sha256_text(
      input.workflow_ref.record_digest +
      ":" +
      input.ability_ref.record_digest +
      ":" +
      input.intake_authority_ref.record_digest +
      ":" +
      receipt.plan_digest,
    ),
    duration_seconds: duration,
    source_refs: [
      input.workflow_ref,
      input.ability_ref,
      input.intake_authority_ref,
    ],
    publication_authority: false,
    external_effect_authorized: false,
    prepared_at,
  }
  ignore(self.handoff_outbox.record_final_deliverable_evidence(evidence))
  let request_id = candidate_id + "-moonflow-handoff"
  let request : @handoff.ExternalHandoffRequest = {
    contract: "mooncast.external-handoff-request.v1",
    record: {
      record_id: request_id,
      record_version: evidence.record.record_version,
      record_digest: "sha256:" +
      sha256_text(request_id + ":" + evidence.record.record_digest),
      provenance_ref: evidence.record.provenance_ref,
    },
    transport_contract: "moonflow.pack-handoff.v1",
    destination_product: "moonbook",
    destination_contract: "moonbook.bookkeeper.v1",
    record_kind: "PackDeliverableCandidateV1",
    subject_ref: evidence.record,
    evidence_refs: [
      evidence.record,
      input.workflow_ref,
      input.ability_ref,
      input.intake_authority_ref,
    ],
    authority_request_ref: None,
    review_receipt_ref: None,
    payload_digest: record_digest,
    requested_at: prepared_at,
    external_effect_authorized: false,
  }
  self.handoff_outbox.prepare_request(request)
}

///|
fn commercial_command(
  snapshot : @commerce.CommercialSnapshot,
  action : String,
  evidence_digest : String,
  lead? : @commerce.QualifiedLead,
  lead_decision? : @commerce.LeadQualificationDecision,
  quote? : @commerce.ScopedQuote,
  quote_decision? : @commerce.QuoteDecision,
  resource? : @commerce.CapacityResource,
  reservation? : @commerce.CapacityReservation,
  capacity_board? : @commerce.CapacityBoard,
  conversion? : @commerce.QuoteConversion,
  portal? : @commerce.ClientPortal,
  billing? : @commerce.MilestoneBillingEntry,
  repeat_order? : @commerce.RepeatOrderProposal,
) -> @commerce.CommercialCommand raise {
  {
    contract: "mooncast.commercial-command.v1",
    command_id: @runtime.new_id(prefix="commercial-command"),
    action,
    recorded_at: now_string(),
    evidence_digest,
    expected_revision: snapshot.revision,
    snapshot,
    lead,
    lead_decision,
    quote,
    quote_decision,
    resource,
    reservation,
    capacity_board,
    conversion,
    portal,
    billing,
    repeat_order,
  }
}

///|
async fn StudioService::create_client_portal_from_ui(
  self : StudioService,
  project_id : String,
  input : ClientPortalCreateInput,
) -> ClientPortalCreateProjection {
  guard input.human_confirmed && input.actor != "" && input.actor_role != "" else {
    fail("named human confirmation is required")
  }
  let canonical = self.get_project(project_id)
  guard canonical.snapshot.revision == input.expected_project_revision else {
    fail("project changed before portal creation")
  }
  guard self.delivery_application.load(input.build_id) is Some(record) &&
    record.build.project_id == project_id &&
    record.build.state == "completed" &&
    normalized_digest(record.build.master_sha256) ==
    normalized_digest(input.expected_master_sha256) &&
    normalized_digest(record.build.build_digest) ==
    normalized_digest(input.expected_build_digest) &&
    normalized_digest(record.build.record_digest) ==
    normalized_digest(input.expected_build_record_digest) else {
    fail("client portal must bind an exact completed delivery build")
  }
  let created_at = now_string()
  let portal_id = @runtime.new_id(prefix="client-portal")
  let record_digest = "sha256:" +
    sha256_text(
      portal_id +
      ":" +
      project_id +
      ":" +
      record.build.build_digest +
      ":" +
      input.expires_at,
    )
  let portal : @commerce.ClientPortal = {
    contract: "mooncast.client-portal.v1",
    portal_id,
    project_id,
    master_sha256: record.build.master_sha256,
    delivery_digest: record.build.delivery_digest,
    build_id: record.build.build_id,
    build_digest: record.build.build_digest,
    client_name: input.client_name,
    brand: { name: input.brand_name, accent: input.brand_accent },
    scopes: ["master-read", "annotation-write", "delivery-decision"],
    expires_at: input.expires_at,
    status: "active",
    revision: 1,
    annotations: [],
    decisions: [],
    created_by: input.actor,
    created_by_role: input.actor_role,
    created_at,
    updated_at: created_at,
    record_digest,
  }
  let snapshot = self.commerce_application.load()
  let created = self.commerce_application.create_client_portal(
    commercial_command(snapshot, "record_client_portal", record_digest, portal~),
  )
  {
    portal: created.portal,
    client_url: created.client_path,
    raw_token_returned_once: created.raw_token_returned_once,
    external_effect_performed: false,
    publication_authority: false,
  }
}

///|
async fn StudioService::control_client_portal_from_ui(
  self : StudioService,
  project_id : String,
  portal_id : String,
  action : String,
  input : ClientPortalControlInput,
) -> @commerce.ClientPortal {
  guard input.human_confirmed && input.actor != "" && input.actor_role != "" else {
    fail("named human confirmation is required")
  }
  let snapshot = self.commerce_application.load()
  let matches = snapshot.portals.filter(portal => {
    portal.portal_id == portal_id && portal.project_id == project_id
  })
  guard matches.length() == 1 &&
    normalized_digest(matches[0].record_digest) ==
    normalized_digest(input.expected_portal_digest) else {
    fail("client portal binding changed")
  }
  let digest = "sha256:" +
    sha256_text(
      portal_id + ":" + action + ":" + input.actor + ":" + now_string(),
    )
  self.commerce_application.control_portal(
    portal_id,
    input.expected_portal_revision,
    action,
    input.actor,
    now_string(),
    digest,
  )
}

///|
async fn StudioService::create_billing_from_ui(
  self : StudioService,
  project_id : String,
  input : BillingCreateInput,
) -> @commerce.MilestoneBillingEntry {
  guard input.human_confirmed && input.actor != "" && input.actor_role != "" else {
    fail("named human confirmation is required")
  }
  let canonical = self.get_project(project_id)
  guard canonical.snapshot.revision == input.expected_project_revision else {
    fail("project changed before billing record creation")
  }
  let created_at = now_string()
  let billing_id = @runtime.new_id(prefix="billing")
  let record_digest = "sha256:" +
    sha256_text(
      billing_id +
      ":" +
      project_id +
      ":" +
      input.kind +
      ":" +
      input.amount.to_string() +
      ":" +
      input.reference,
    )
  let history : Array[@commerce.BillingHistoryEntry] = [
    {
      state: input.state,
      actor: input.actor,
      actor_role: input.actor_role,
      reference: input.reference,
      recorded_at: created_at,
    },
  ]
  let entry : @commerce.MilestoneBillingEntry = {
    contract: "mooncast.milestone-billing-entry.v1",
    billing_id,
    project_id,
    kind: input.kind,
    currency: input.currency,
    amount: input.amount,
    reference: input.reference,
    state: input.state,
    quoted_at: created_at,
    due_at: input.due_at,
    paid_at: if input.state == "paid" {
      Some(created_at)
    } else {
      None
    },
    waived_at: if input.state == "waived" {
      Some(created_at)
    } else {
      None
    },
    history,
    revision: 1,
    record_digest,
    payment_effect_performed: false,
  }
  let snapshot = self.commerce_application.load()
  ignore(
    self.commerce_application.submit(
      commercial_command(
        snapshot,
        "record_billing",
        record_digest,
        billing=entry,
      ),
    ),
  )
  entry
}

///|
async fn StudioService::transition_billing_from_ui(
  self : StudioService,
  project_id : String,
  billing_id : String,
  input : BillingTransitionInput,
) -> @commerce.MilestoneBillingEntry {
  guard input.human_confirmed && input.actor != "" && input.actor_role != "" else {
    fail("named human confirmation is required")
  }
  let matches = self.commerce_application
    .billing_for_project(project_id)
    .filter(entry => entry.billing_id == billing_id)
  guard matches.length() == 1 &&
    normalized_digest(matches[0].record_digest) ==
    normalized_digest(input.expected_billing_digest) else {
    fail("billing record binding changed")
  }
  let digest = "sha256:" +
    sha256_text(
      billing_id + ":" + input.state + ":" + input.actor + ":" + input.reference,
    )
  self.commerce_application.transition_billing(
    billing_id,
    input.expected_billing_revision,
    input.state,
    input.actor,
    input.actor_role,
    input.reference,
    now_string(),
    digest,
  )
}

///|
fn delivery_artifact_projection(
  artifact : @execution.DeliveryBuildArtifact,
) -> DeliveryArtifactProjection {
  {
    artifact_id: artifact.artifact_id,
    kind: artifact.kind,
    name: artifact.filename,
    media_type: artifact.media_type,
    size_bytes: artifact.bytes,
    sha256: artifact.digest,
  }
}

///|
fn delivery_build_projection(
  build : @execution.DeliveryBuild,
) -> DeliveryBuildProjection {
  {
    contract: build.contract,
    build_id: build.build_id,
    build_digest: build.build_digest,
    project_id: build.project_id,
    project_revision: build.project_revision,
    master_sha256: build.master_sha256,
    delivery_version: build.delivery_version,
    delivery_digest: build.delivery_digest,
    profile_version: build.profile.profile_version,
    profile_digest: build.profile.profile_digest,
    state: build.state,
    revision: build.revision,
    attempt_count: build.attempt_count,
    recovery_count: build.recovery_count,
    artifacts: build.artifacts.map(delivery_artifact_projection),
    archive: build.archive.map(delivery_artifact_projection),
    download_url: if build.state == "completed" {
      Some(
        "/api/v2/projects/" +
        build.project_id +
        "/delivery-builds/" +
        build.build_id +
        "/download",
      )
    } else {
      None
    },
    economics_receipt: build.economics_receipt_digest,
    last_error: build.last_error_code,
    created_at: build.created_at,
    updated_at: build.updated_at,
    publication_authority: false,
    record_digest: build.record_digest,
  }
}

///|
fn delivery_output(
  output_id : String,
  kind : String,
  width : Int,
  height : Int,
  subtitle_mode : String,
  metadata_digest : String,
) -> @execution.DeliveryOutputSpec {
  {
    output_id,
    kind,
    container: "mp4",
    codec: "libx264",
    width,
    height,
    subtitle_mode,
    metadata_digest,
    source_output_id: None,
    orientation: None,
    framing_policy: None,
    in_seconds: None,
    out_seconds: None,
    timestamp_seconds: None,
  }
}

///|
async fn StudioService::create_delivery_from_ui(
  self : StudioService,
  project_id : String,
  input : DeliveryCreateInput,
) -> DeliveryBuildProjection {
  let canonical = self.get_project(project_id)
  guard canonical.snapshot.revision == input.expected_project_revision &&
    canonical.snapshot.master is Some(master) &&
    canonical.snapshot.delivery_package is Some(delivery) else {
    fail("an exact accepted master and delivery package are required")
  }
  guard normalized_digest(master.video_digest) ==
    normalized_digest(input.expected_master_sha256) &&
    delivery.reference.version == input.expected_delivery_version &&
    normalized_digest(delivery.reference.digest) ==
    normalized_digest(input.expected_delivery_digest) else {
    fail("delivery build inputs changed")
  }
  guard input.profile.contract == "mooncast.delivery-build-profile.v1" &&
    input.profile.variants.all(variant => {
      variant.policy == "crop" ||
      variant.policy == "pad" ||
      variant.policy == "scale"
    }) else {
    fail("delivery build profile contract or variant policy is invalid")
  }
  let outputs : Array[@execution.DeliveryOutputSpec] = []
  let subtitle_mode = if input.profile.include_subtitles {
    "burned"
  } else {
    "none"
  }
  if input.profile.include_source_master {
    outputs.push(
      delivery_output(
        "master",
        "source-master",
        1920,
        1080,
        subtitle_mode,
        "sha256:" +
        sha256_text(project_id + ":master:" + input.profile.version.to_string()),
      ),
    )
  }
  for variant in input.profile.variants {
    let output = delivery_output(
      variant.variant_id,
      "platform-variant",
      variant.width,
      variant.height,
      subtitle_mode,
      "sha256:" + sha256_text(variant.to_json().stringify()),
    )
    outputs.push({
      ..output,
      orientation: Some(variant.orientation),
      framing_policy: Some(variant.policy),
    })
  }
  for cut in input.profile.cuts {
    let output = delivery_output(
      cut.cut_id,
      "channel-cut",
      1920,
      1080,
      subtitle_mode,
      "sha256:" + sha256_text(cut.to_json().stringify()),
    )
    outputs.push({
      ..output,
      source_output_id: Some(cut.source_variant),
      in_seconds: Some(cut.in_seconds),
      out_seconds: Some(cut.out_seconds),
    })
  }
  for cover in input.profile.covers {
    outputs.push({
      output_id: cover.cover_id,
      kind: "cover-frame",
      container: cover.format,
      codec: if cover.format == "png" {
        "png"
      } else {
        "mjpeg"
      },
      width: 1280,
      height: 720,
      subtitle_mode: "none",
      metadata_digest: "sha256:" + sha256_text(cover.to_json().stringify()),
      source_output_id: Some(cover.source_variant),
      orientation: None,
      framing_policy: Some("scale"),
      in_seconds: None,
      out_seconds: None,
      timestamp_seconds: Some(cover.timestamp_seconds),
    })
  }
  if outputs.is_empty() {
    outputs.push(
      delivery_output(
        "master",
        "source-master",
        1920,
        1080,
        subtitle_mode,
        "sha256:" + sha256_text(project_id + ":default-master"),
      ),
    )
  }
  let profile_digest = "sha256:" +
    sha256_text(input.profile.to_json().stringify())
  let profile : @execution.DeliveryBuildProfile = {
    contract: "mooncast.delivery-build-profile.v1",
    profile_version: input.profile.version,
    profile_digest,
    outputs,
    include_provenance_manifest: input.profile.include_provenance_rights_ai_manifest,
    include_rights_ledger: input.profile.include_provenance_rights_ai_manifest,
    include_acceptance_receipt: true,
  }
  let master_path = self.editor_export_path_for_digest(
    project_id,
    master.video_digest,
  )
  let request : @execution_app.DeliveryBuildRequest = {
    contract: "mooncast.delivery-build-request.v1",
    project_id,
    expected_project_revision: canonical.snapshot.revision,
    master_path,
    master_sha256: normalized_digest(master.video_digest),
    master_promotion_digest: normalized_digest(master.reference.digest),
    master_duration_seconds: master.duration_seconds.to_double(),
    delivery_version: delivery.reference.version,
    delivery_digest: normalized_digest(delivery.reference.digest),
    profile,
    subtitle_path: None,
    project_metadata: Some(
      Json::object({
        "project_id": project_id.to_json(),
        "title": canonical.snapshot.graph.title.to_json(),
        "target_duration_seconds": canonical.snapshot.graph.target_duration_seconds.to_json(),
        "profile_digest": profile_digest.to_json(),
      }),
    ),
    provenance_manifest: Some(
      Json::object({
        "master_digest": master.video_digest.to_json(),
        "master_provenance_digest": master.provenance_digest.to_json(),
        "delivery_manifest_digest": delivery.manifest_digest.to_json(),
      }),
    ),
    rights_ledger: Some(
      Json::object({
        "rights_ledger_digest": delivery.rights_ledger_digest.to_json(),
        "source_asset_digests": canonical.snapshot.graph.assets
        .map(asset => asset.digest)
        .to_json(),
      }),
    ),
    acceptance_receipt: Some(
      Json::object({
        "contract": "mooncast.delivery-acceptance-receipt-template.v1".to_json(),
        "project_id": project_id.to_json(),
        "master_sha256": master.video_digest.to_json(),
        "delivery_digest": delivery.reference.digest.to_json(),
        "state": "awaiting-named-client-acceptance".to_json(),
        "publication_authority": false.to_json(),
      }),
    ),
    ai_label: Some(master.ai_label),
    g5_accepted: @governance.master_exact_approved(
      canonical.snapshot.master,
      canonical.snapshot.master_decisions,
    ),
    client_accepted: @governance.delivery_exact_accepted(
      canonical.snapshot.delivery_package,
      canonical.snapshot.master,
      canonical.snapshot.delivery_acceptances,
    ),
    evidence_digest: "sha256:" +
    sha256_text(
      delivery.manifest_digest +
      ":" +
      delivery.rights_ledger_digest +
      ":" +
      profile_digest,
    ),
    created_at: now_string(),
  }
  delivery_build_projection(self.delivery_application.create(request).build)
}

///|
async fn StudioService::run_delivery_action_from_ui(
  self : StudioService,
  project_id : String,
  build_id : String,
  action : String,
  input : DeliveryActionInput,
) -> DeliveryBuildProjection {
  guard input.actor != "" &&
    self.delivery_application.load(build_id) is Some(record) &&
    record.build.project_id == project_id &&
    normalized_digest(record.build.record_digest) ==
    normalized_digest(input.expected_record_digest) else {
    fail("delivery action does not bind the current build")
  }
  let economics_digest = "sha256:" +
    sha256_text(
      build_id +
      ":" +
      action +
      ":" +
      input.actor +
      ":" +
      input.expected_build_revision.to_string(),
    )
  let updated = match action {
    "build" =>
      self.delivery_application.build(
        build_id,
        input.expected_build_revision,
        record.build.record_digest,
        economics_digest,
      )
    "retry" =>
      self.delivery_application.retry(
        build_id,
        input.expected_build_revision,
        record.build.record_digest,
        economics_digest,
      )
    "cancel" =>
      self.delivery_application.cancel(
        build_id,
        input.expected_build_revision,
        record.build.record_digest,
      )
    _ => fail("unsupported delivery action")
  }
  delivery_build_projection(updated.build)
}

///|
async fn StudioService::accept_delivery_from_ui(
  self : StudioService,
  project_id : String,
  build_id : String,
  input : DeliveryAcceptanceInput,
) -> DeliveryAcceptanceProjection {
  guard input.human_confirmed &&
    input.actor != "" &&
    input.actor_role != "" &&
    self.delivery_application.load(build_id) is Some(record) &&
    record.build.project_id == project_id &&
    record.build.project_revision == input.expected_project_revision &&
    normalized_digest(record.build.build_digest) ==
    normalized_digest(input.expected_build_digest) &&
    normalized_digest(record.build.record_digest) ==
    normalized_digest(input.expected_build_record_digest) else {
    fail("delivery acceptance does not bind the current completed build")
  }
  let decided_at = now_string()
  let receipt_digest = "sha256:" +
    sha256_text(
      build_id +
      ":" +
      input.decision +
      ":" +
      input.actor +
      ":" +
      input.note +
      ":" +
      decided_at,
    )
  let acceptance : @execution.DeliveryBuildAcceptance = {
    contract: "mooncast.delivery-build-acceptance.v1",
    build_digest: record.build.build_digest,
    build_record_digest: record.build.record_digest,
    decision: input.decision,
    actor: input.actor,
    actor_role: input.actor_role,
    note: input.note,
    project_revision: record.build.project_revision,
    decided_at,
    receipt_digest,
  }
  ignore(self.delivery_application.record_acceptance(build_id, acceptance))
  {
    project: self.studio_project_projection(self.get_project(project_id)),
    build: delivery_build_projection(record.build),
    acceptance,
    publication_authority: false,
  }
}

///|
fn routed_job_projection(job : @execution.ProviderExecutionJob) -> Json {
  let attempts : Array[Json] = []
  let mut ordinal = 1
  for attempt in job.attempt_history {
    attempts.push(
      Json::object({
        "ordinal": ordinal.to_json(),
        "attempt_id": attempt.attempt_id.to_json(),
        "phase": attempt.phase.to_json(),
        "state": attempt.state.to_json(),
        "started_at": attempt.start_timestamp.to_json(),
        "ended_at": attempt.end_timestamp.to_json(),
        "normalized_error": match attempt.error_code {
          Some(code) =>
            Json::object({
              "code": code.to_json(),
              "message": attempt.error_message.unwrap_or("").to_json(),
            })
          None => Json::null()
        },
        "phase_digest": attempt.phase_digest.to_json(),
        "usage_cost_receipt_digest": attempt.usage_cost_receipt_digest.to_json(),
        "attachment_receipt_digest": attempt.attachment_receipt_digest.to_json(),
      }),
    )
    ordinal = ordinal + 1
  }
  Json::object({
    "job_id": job.job_id.to_json(),
    "state": job.state.to_json(),
    "revision": job.revision.to_json(),
    "attempt_count": job.attempt_count.to_json(),
    "maximum_attempts": job.max_attempts.to_json(),
    "spent_cny": job.spent_cny.to_json(),
    "artifact_digests": job.artifacts
    .map(item => item.artifact_digest)
    .to_json(),
    "attempt_history": attempts.to_json(),
    "last_error": match job.last_error_code {
      Some(code) =>
        Json::object({
          "code": code.to_json(),
          "message": job.last_error_message.unwrap_or("").to_json(),
        })
      None => Json::null()
    },
    "project_ingest": match job.project_ingest_digest {
      Some(digest) => Json::object({ "digest": digest.to_json() })
      None => Json::null()
    },
    "publication_authority": false.to_json(),
  })
}

///|
async fn StudioService::routed_execution_projection(
  self : StudioService,
  execution : @execution.RoutedExecution,
) -> Json {
  // Routed executions are created in canonical graph order. Keep that order in
  // the wire projection so list, create, get and action responses share the
  // same array contract consumed by Studio.
  let shots : Array[Json] = []
  let jobs : Map[String, Json] = Map([])
  for binding in execution.shots {
    match self.execution_application.load_job(binding.job_id) {
      Some(record) => {
        let job = record.job
        let route_digest = "sha256:" +
          sha256_text(
            binding.route_id +
            ":" +
            job.plan.provider +
            ":" +
            job.plan.model +
            ":" +
            binding.cost_ceiling_cny.to_string(),
          )
        shots.push(
          Json::object({
            "shot_id": binding.shot_id.to_json(),
            "route_id": binding.route_id.to_json(),
            "route_digest": route_digest.to_json(),
            "job_id": binding.job_id.to_json(),
            "adapter_id": job.plan.adapter_id.to_json(),
            "provider": job.plan.provider.to_json(),
            "model": job.plan.model.to_json(),
            "maximum_attempts": job.max_attempts.to_json(),
            "cost_ceiling_cny": binding.cost_ceiling_cny.to_json(),
          }),
        )
        jobs[binding.shot_id] = routed_job_projection(job)
      }
      None => {
        shots.push(
          Json::object({
            "shot_id": binding.shot_id.to_json(),
            "route_id": binding.route_id.to_json(),
            "route_digest": execution.binding_digest.to_json(),
            "job_id": binding.job_id.to_json(),
            "adapter_id": "unresolved".to_json(),
            "provider": "unresolved".to_json(),
            "model": "unresolved".to_json(),
            "maximum_attempts": (0).to_json(),
            "cost_ceiling_cny": binding.cost_ceiling_cny.to_json(),
          }),
        )
        jobs[binding.shot_id] = Json::object({
          "job_id": binding.job_id.to_json(),
          "state": "missing".to_json(),
          "attempt_count": (0).to_json(),
          "attempt_history": Json::array([]),
          "artifact_digests": Json::array([]),
          "publication_authority": false.to_json(),
        })
      }
    }
  }
  Json::object({
    "contract": execution.contract.to_json(),
    "execution_id": execution.execution_id.to_json(),
    "project_id": execution.project_id.to_json(),
    "project_revision_anchor": execution.project_revision_anchor.to_json(),
    "routing_plan_version": execution.routing_plan.version.to_json(),
    "routing_plan_digest": execution.routing_plan.digest.to_json(),
    "binding_digest": execution.binding_digest.to_json(),
    "aggregate_cost_ceiling_cny": execution.aggregate_cost_ceiling_cny.to_json(),
    "currency": execution.currency.to_json(),
    "actor_id": execution.actor_id.to_json(),
    "state": execution.state.to_json(),
    "revision": execution.revision.to_json(),
    "shots": shots.to_json(),
    "job_state": Json::object(jobs),
    "created_at": execution.created_at.to_json(),
    "updated_at": execution.updated_at.to_json(),
    "publication_authority": false.to_json(),
    "record_digest": execution.record_digest.to_json(),
  })
}

///|
pub async fn StudioService::dispatch_application_http(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response? {
  let segments = path_segments(request.path)
  match (request.request_method, segments) {
    (Get, ["api", "provider-executions", "config"]) =>
      Some(@app_http.provider_config_handler(self.execution_application))
    (Get, ["api", "provider-executions"]) => {
      let projection : ProviderJobsProjection = {
        jobs: self.execution_application.list_jobs(),
        publication_authority: false,
      }
      Some(json_value_response(200, projection))
    }
    (Post, ["api", "provider-executions"]) =>
      Some(
        @app_http.provider_authorize_handler(
          self.execution_application,
          request,
        ),
      )
    (Get, ["api", "provider-executions", job_id]) =>
      Some(@app_http.provider_get_handler(self.execution_application, job_id))
    (Post, ["api", "provider-executions", job_id, "execute"]) =>
      Some(
        @app_http.provider_action_handler(
          self.execution_application,
          job_id,
          "execute",
          request,
        ),
      )
    (Post, ["api", "provider-executions", job_id, "resume"]) =>
      Some(
        @app_http.provider_action_handler(
          self.execution_application,
          job_id,
          "resume",
          request,
        ),
      )
    (Post, ["api", "provider-executions", job_id, "cancel"]) =>
      Some(
        @app_http.provider_action_handler(
          self.execution_application,
          job_id,
          "cancel",
          request,
        ),
      )
    (
      Get,
      ["api", "v2", "projects", project_id, "governance", "stages", stage]
      | ["api", "v2", "projects", project_id, "governance", stage],
    ) =>
      Some(
        json_value_response(
          200,
          self.governance_stage_projection(project_id, stage),
        ),
      )
    (
      Post,
      ["api", "v2", "projects", project_id, "governance", "model-routing"]
      | [
        "api",
        "v2",
        "projects",
        project_id,
        "governance",
        "model-routing",
        "revise",
      ],
    ) => {
      let input : RoutingPlanRecordInput = decode_body(request)
      let response = self.record_routing_plan_feature(project_id, input)
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "governance",
        "model-routing",
        "decisions",
      ],
    ) => {
      let input : RoutingDecisionInput = decode_body(request)
      let response = self.record_routing_decision_feature(project_id, input)
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "governance",
        "shots",
        shot_id,
        "attempts",
      ],
    ) => {
      let input : GenerationAttemptInput = decode_body(request)
      let response = self.record_generation_attempt_feature(
        project_id, shot_id, input,
      )
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "governance",
        "shots",
        shot_id,
        "qc",
        dimension,
        "findings",
      ],
    ) => {
      guard qc_dimension_from_path(dimension) is Some(value) else {
        return Some(
          api_error(
            422, "qc_dimension_invalid", "dimension must be technical, continuity, safety, claims, or rights",
          ),
        )
      }
      let input : QcFindingInput = decode_body(request)
      let response = self.record_qc_finding_feature(
        project_id, shot_id, value, input,
      )
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "governance",
        "shots",
        shot_id,
        "qc",
        dimension,
        "decisions"
        | "decision",
      ],
    ) => {
      guard qc_dimension_from_path(dimension) is Some(value) else {
        return Some(
          api_error(
            422, "qc_dimension_invalid", "dimension must be technical, continuity, safety, claims, or rights",
          ),
        )
      }
      let input : QcDecisionInput = decode_body(request)
      let response = self.record_qc_decision_feature(
        project_id, shot_id, value, input,
      )
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "governance", "master"]) => {
      let input : MasterRecordInput = decode_body(request)
      let response = self.record_master_feature(project_id, input)
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (
      Post,
      ["api", "v2", "projects", project_id, "governance", "master", kind]
      | [
        "api",
        "v2",
        "projects",
        project_id,
        "governance",
        "master",
        kind,
        "decisions",
      ],
    ) => {
      let input : MasterDecisionInput = decode_body(request)
      let response = self.record_master_decision_feature(
        project_id, kind, input,
      )
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (
      Post,
      ["api", "v2", "projects", project_id, "governance", "delivery-package"],
    ) => {
      let input : DeliveryPackageRecordInput = decode_body(request)
      let response = self.record_delivery_package_feature(project_id, input)
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "governance",
        "delivery-milestone"
        | "delivery-milestones",
      ],
    ) => {
      let input : DeliveryMilestoneInput = decode_body(request)
      let response = self.record_delivery_milestone_feature(project_id, input)
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "governance",
        "publication-authorizations",
      ],
    ) => {
      let input : PublicationAuthorizationInput = decode_body(request)
      let response = self.record_publication_authorization_feature(
        project_id, input,
      )
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "governance",
        "publication-observations",
      ],
    ) => {
      let input : PublicationObservationInput = decode_body(request)
      let response = self.record_publication_observation_feature(
        project_id, input,
      )
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "governance",
        "performance-review"
        | "performance-reviews",
      ],
    ) => {
      let input : PerformanceReviewInput = decode_body(request)
      let response = self.record_performance_review_feature(project_id, input)
      Some(
        json_value_response(
          if response.result.ok {
            200
          } else {
            422
          },
          self.project_command_ui(response),
        ),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "delivery", "outcome-handoff"]) => {
      let input : OutcomeHandoffPrepareInput = decode_body(request)
      Some(
        json_value_response(
          201,
          self.prepare_production_outcome_handoff(project_id, input),
        ),
      )
    }
    (Get, ["api", "v2", "projects", project_id, "routed-executions"]) => {
      let executions : Array[Json] = []
      for
        execution in self.execution_application.list_routed_executions(
          project_id,
        ) {
        executions.push(self.routed_execution_projection(execution))
      }
      let projection : RoutedExecutionsProjection = {
        executions,
        publication_authority: false,
      }
      Some(json_value_response(200, projection))
    }
    (Post, ["api", "v2", "projects", project_id, "routed-executions"]) => {
      let input : RoutedCreateRequest = decode_body(request)
      let canonical = self.get_project(project_id)
      guard canonical.snapshot.revision == input.expected_project_revision else {
        return Some(
          api_error(
            409, "routed_project_revision_conflict", "project changed before routed execution creation",
          ),
        )
      }
      guard canonical.snapshot.routing_plan is Some(routing) else {
        return Some(
          api_error(
            409, "routed_plan_missing", "an approved model routing plan is required",
          ),
        )
      }
      guard routing.reference.version == input.expected_routing_plan_version &&
        normalized_digest(routing.reference.digest) ==
        normalized_digest(input.expected_routing_plan_digest) else {
        return Some(
          api_error(
            409, "routed_plan_stale", "the approved model routing plan changed",
          ),
        )
      }
      guard gate_recorded(canonical.snapshot, "G3") &&
        @governance.routing_exact_approved(
          canonical.snapshot.routing_plan,
          canonical.snapshot.routing_decisions,
          canonical.snapshot.graph.maximum_budget_cny,
        ) else {
        return Some(
          api_error(
            409, "routed_plan_not_approved", "G3 and independent producer/finance approvals are required",
          ),
        )
      }
      guard !input.publication_authority else {
        return Some(
          api_error(
            403, "routed_publication_denied", "routed generation never grants publication authority",
          ),
        )
      }
      guard self.approved_rendered_animatic(project_id)
        is Some(animatic_approval) else {
        return Some(
          api_error(
            409, "routed_animatic_not_approved", "expensive shot generation requires the exact approved rendered animatic",
          ),
        )
      }
      let approved_animatic_digest = animatic_approval.rendered.video_digest
      let binding_digest = "sha256:" +
        sha256_text(
          project_id +
          ":" +
          canonical.snapshot.revision.to_string() +
          ":" +
          routing.reference.digest +
          ":" +
          approved_animatic_digest +
          ":" +
          input.actor_id,
        )
      let approved_assets_by_shot = self.approved_asset_map(
        project_id,
        canonical.snapshot.revision,
      )
      let record = self.execution_application.create_routed_from_catalog(
        canonical.snapshot.graph,
        routing,
        input.actor_id,
        binding_digest,
        input.network_authority,
        approved_assets_by_shot~,
        approved_animatic_digest~,
      )
      Some(
        json_value_response(
          201,
          self.routed_execution_projection(record.execution),
        ),
      )
    }
    (
      Get,
      ["api", "v2", "projects", project_id, "routed-executions", execution_id],
    ) =>
      match self.execution_application.load_routed_execution(execution_id) {
        Some(record) if record.execution.project_id == project_id =>
          Some(
            json_value_response(
              200,
              self.routed_execution_projection(record.execution),
            ),
          )
        _ =>
          Some(
            api_error(
              404, "routed_execution_not_found", "routed execution was not found",
            ),
          )
      }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "routed-executions",
        execution_id,
        "shots",
        shot_id,
        "execute",
      ],
    ) => {
      let payload : RoutedActionRequest = decode_body(request)
      guard self.execution_application.load_routed_execution(execution_id)
        is Some(current) &&
        current.execution.project_id == project_id &&
        (match payload.expected_execution_digest {
          Some(value) =>
            normalized_digest(value) ==
            normalized_digest(current.execution.record_digest)
          None => true
        }) else {
        return Some(
          api_error(
            409, "routed_execution_conflict", "routed execution binding changed",
          ),
        )
      }
      let pipeline_result = self.production_pipeline.routed_action_and_ingest(
        project_id,
        execution_id,
        shot_id,
        "execute",
        payload.expected_execution_revision,
        payload.actor_id,
      )
      ignore(self.adopt_pipeline_result(project_id, pipeline_result))
      let execution = pipeline_result.execution
      guard execution.shots.filter(binding => binding.shot_id == shot_id).get(0)
        is Some(binding) &&
        self.execution_application.load_job(binding.job_id) is Some(job) else {
        return Some(
          api_error(409, "routed_job_missing", "routed provider job is missing"),
        )
      }
      Some(
        json_value_response(200, RoutedActionProjection::{
          execution: self.routed_execution_projection(execution),
          job: routed_job_projection(job.job),
          publication_authority: false,
        }),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "routed-executions",
        execution_id,
        "shots",
        shot_id,
        "resume",
      ],
    ) => {
      let payload : RoutedActionRequest = decode_body(request)
      guard self.execution_application.load_routed_execution(execution_id)
        is Some(current) &&
        current.execution.project_id == project_id else {
        return Some(
          api_error(
            404, "routed_execution_not_found", "routed execution was not found",
          ),
        )
      }
      let pipeline_result = self.production_pipeline.routed_action_and_ingest(
        project_id,
        execution_id,
        shot_id,
        "resume",
        payload.expected_execution_revision,
        payload.actor_id,
      )
      ignore(self.adopt_pipeline_result(project_id, pipeline_result))
      let execution = pipeline_result.execution
      guard execution.shots.filter(binding => binding.shot_id == shot_id).get(0)
        is Some(binding) &&
        self.execution_application.load_job(binding.job_id) is Some(job) else {
        return Some(
          api_error(409, "routed_job_missing", "routed provider job is missing"),
        )
      }
      Some(
        json_value_response(200, RoutedActionProjection::{
          execution: self.routed_execution_projection(execution),
          job: routed_job_projection(job.job),
          publication_authority: false,
        }),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "routed-executions",
        execution_id,
        "shots",
        shot_id,
        "cancel",
      ],
    ) => {
      let payload : RoutedActionRequest = decode_body(request)
      guard self.execution_application.load_routed_execution(execution_id)
        is Some(current) &&
        current.execution.project_id == project_id else {
        return Some(
          api_error(
            404, "routed_execution_not_found", "routed execution was not found",
          ),
        )
      }
      let record = self.execution_application.routed_action(
        execution_id,
        shot_id,
        "cancel",
        payload.expected_execution_revision,
        payload.actor_id,
      )
      guard record.execution.shots
        .filter(binding => binding.shot_id == shot_id)
        .get(0)
        is Some(binding) &&
        self.execution_application.load_job(binding.job_id) is Some(job) else {
        return Some(
          api_error(409, "routed_job_missing", "routed provider job is missing"),
        )
      }
      Some(
        json_value_response(200, RoutedActionProjection::{
          execution: self.routed_execution_projection(record.execution),
          job: routed_job_projection(job.job),
          publication_authority: false,
        }),
      )
    }
    (Get, ["api", "v2", "projects", project_id, "delivery-builds"]) =>
      Some(
        json_value_response(200, DeliveryBuildsProjection::{
          builds: self.delivery_application
          .list(project_id)
          .map(delivery_build_projection),
          publication_authority: false,
        }),
      )
    (Post, ["api", "v2", "projects", project_id, "delivery-builds"]) => {
      let json = @json.parse(@utf8.decode(request.body))
      if json is Object(values) && values.get("contract") is Some(_) {
        let input : @execution_app.DeliveryBuildRequest = @json.from_json(json)
        if input.project_id != project_id {
          Some(
            api_error(
              422, "delivery_project_mismatch", "delivery build must bind the route project",
            ),
          )
        } else {
          Some(
            json_value_response(
              201,
              delivery_build_projection(
                self.delivery_application.create(input).build,
              ),
            ),
          )
        }
      } else {
        let input : DeliveryCreateInput = @json.from_json(json)
        Some(
          json_value_response(
            201,
            self.create_delivery_from_ui(project_id, input),
          ),
        )
      }
    }
    (Get, ["api", "v2", "projects", project_id, "delivery-builds", build_id]) =>
      match self.delivery_application.load(build_id) {
        Some(record) if record.build.project_id == project_id =>
          Some(
            json_value_response(200, delivery_build_projection(record.build)),
          )
        _ =>
          Some(
            api_error(
              404, "delivery_build_not_found", "delivery build was not found",
            ),
          )
      }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "delivery-builds",
        build_id,
        "build",
      ],
    ) => {
      let input : DeliveryActionInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.run_delivery_action_from_ui(project_id, build_id, "build", input),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "delivery-builds",
        build_id,
        "retry",
      ],
    ) => {
      let input : DeliveryActionInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.run_delivery_action_from_ui(project_id, build_id, "retry", input),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "delivery-builds",
        build_id,
        "cancel",
      ],
    ) => {
      let input : DeliveryActionInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.run_delivery_action_from_ui(
            project_id, build_id, "cancel", input,
          ),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "delivery-builds",
        build_id,
        "acceptance",
      ],
    ) => {
      let input : DeliveryAcceptanceInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.accept_delivery_from_ui(project_id, build_id, input),
        ),
      )
    }
    (Get, ["api", "v2", "projects", _, "delivery-builds", build_id, "download"]) =>
      Some(
        @app_http.delivery_download_handler(self.delivery_application, build_id),
      )
    (Get, ["api", "commercial-intake"]) =>
      Some(json_value_response(200, self.commercial_dashboard_projection()))
    (Get, ["api", "commercial-intake", "capacity-board"]) =>
      Some(json_value_response(200, self.commerce_application.capacity_board()))
    (Get, ["api", "commercial-intake", "leads", lead_id]) =>
      Some(json_value_response(200, self.commercial_lead_projection(lead_id)))
    (Get, ["api", "commercial-intake", "quotes", quote_id]) =>
      Some(json_value_response(200, self.commercial_quote_projection(quote_id)))
    (Get, ["api", "commercial-intake", "quotes", quote_id, "capacity-board"]) =>
      Some(json_value_response(200, self.capacity_board_projection(quote_id)))
    (Get, ["api", "v2", "projects", project_id, "client-portals"]) => {
      let snapshot = self.commerce_application.load()
      let projection : PortalsProjection = {
        portals: snapshot.portals.filter(portal => {
          portal.project_id == project_id
        }),
        publication_authority: false,
      }
      Some(json_value_response(200, projection))
    }
    (Get, ["api", "v2", "projects", project_id, "billing"]) => {
      let projection : BillingProjection = {
        entries: self.commerce_application.billing_for_project(project_id),
        payment_effect_performed: false,
      }
      Some(json_value_response(200, projection))
    }
    (Post, ["api", "v2", "projects", project_id, "client-portals"]) => {
      let input : ClientPortalCreateInput = decode_body(request)
      Some(
        json_value_response(
          201,
          self.create_client_portal_from_ui(project_id, input),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "client-portals",
        portal_id,
        "revoke",
      ],
    ) => {
      let input : ClientPortalControlInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.control_client_portal_from_ui(
            project_id, portal_id, "revoke", input,
          ),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "client-portals",
        portal_id,
        "expire",
      ],
    ) => {
      let input : ClientPortalControlInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.control_client_portal_from_ui(
            project_id, portal_id, "expire", input,
          ),
        ),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "billing"]) => {
      let input : BillingCreateInput = decode_body(request)
      Some(
        json_value_response(201, self.create_billing_from_ui(project_id, input)),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "billing", billing_id, "state"]
    ) => {
      let input : BillingTransitionInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.transition_billing_from_ui(project_id, billing_id, input),
        ),
      )
    }
    (Post, ["api", "commercial-intake", "leads"]) => {
      let input : LeadCreateInput = decode_body(request)
      Some(json_value_response(201, self.create_commercial_lead(input)))
    }
    (Post, ["api", "commercial-intake", "leads", lead_id, "qualification"]) => {
      let input : HumanDecisionInput = decode_body(request)
      Some(
        json_value_response(200, self.qualify_commercial_lead(lead_id, input)),
      )
    }
    (Post, ["api", "commercial-intake", "leads", lead_id, "quotes"]) => {
      let input : QuoteInput = decode_body(request)
      Some(
        json_value_response(
          201,
          self.create_or_revise_quote(lead_id, None, input),
        ),
      )
    }
    (Post, ["api", "commercial-intake", "quotes", quote_id, "revisions"]) => {
      let input : QuoteInput = decode_body(request)
      let quote = self.commercial_quote_projection(quote_id)
      Some(
        json_value_response(
          201,
          self.create_or_revise_quote(
            quote.source_lead_id,
            Some(quote_id),
            input,
          ),
        ),
      )
    }
    (
      Post,
      ["api", "commercial-intake", "quotes", quote_id, "internal-decisions"],
    ) => {
      let input : HumanDecisionInput = decode_body(request)
      guard input.authority is Some(authority) else {
        return Some(
          api_error(
            422, "quote_authority_required", "commercial or production authority is required",
          ),
        )
      }
      Some(
        json_value_response(
          200,
          self.decide_commercial_quote(quote_id, authority, input),
        ),
      )
    }
    (Post, ["api", "commercial-intake", "quotes", quote_id, "client-acceptance"]
    ) => {
      let input : HumanDecisionInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.decide_commercial_quote(quote_id, "client", input),
        ),
      )
    }
    (Post, ["api", "commercial-intake", "capacity", "resources"]) => {
      let input : ResourceInput = decode_body(request)
      Some(json_value_response(201, self.create_capacity_resource(input)))
    }
    (Post, ["api", "commercial-intake", "capacity", "reservations"]) => {
      let input : ReservationInput = decode_body(request)
      Some(json_value_response(201, self.create_capacity_reservation(input)))
    }
    (
      Post,
      [
        "api",
        "commercial-intake",
        "capacity",
        "reservations",
        reservation_id,
        "reschedule",
      ],
    ) => {
      let input : ReservationRescheduleInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.reschedule_capacity_reservation(reservation_id, input),
        ),
      )
    }
    (Post, ["api", "commercial-intake", "quotes", quote_id, "conversion"]) => {
      let input : QuoteConversionInput = decode_body(request)
      Some(
        json_value_response(201, self.convert_commercial_quote(quote_id, input)),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "repeat-orders"]) => {
      let input : RepeatOrderInput = decode_body(request)
      Some(
        json_value_response(201, self.create_repeat_order(project_id, input)),
      )
    }
    (
      Post,
      ["api", "commercial-intake", ..]
      | ["api", "v2", "projects", _, "client-portals", ..]
      | ["api", "v2", "projects", _, "billing", ..],
    ) =>
      Some(
        @app_http.commercial_command_handler(self.commerce_application, request),
      )
    (Get, ["api", "client", token]) =>
      Some(json_value_response(200, self.client_workspace(token)))
    (Get | Head, ["api", "client", token, "master"]) =>
      Some(self.serve_client_master(token, request))
    (Post, ["api", "client", token, "annotations"]) =>
      Some(
        json_value_response(
          201,
          self.record_client_annotation_from_ui(token, decode_body(request)),
        ),
      )
    (Post, ["api", "client", token, "decision"]) =>
      Some(
        json_value_response(
          200,
          self.record_client_decision_from_ui(token, decode_body(request)),
        ),
      )
    (Get, ["api", "client", token, "download"]) => {
      let (_, build) = self.client_binding(token)
      Some(
        @app_http.delivery_download_handler(
          self.delivery_application,
          build.build.build_id,
        ),
      )
    }
    (Post, ["api", "handoffs", "final-deliverables"]) =>
      Some(
        @app_http.final_deliverable_evidence_handler(
          self.handoff_outbox,
          request,
        ),
      )
    (Post, ["api", "handoffs", "outcomes"]) =>
      Some(
        @app_http.production_outcome_evidence_handler(
          self.handoff_outbox,
          request,
        ),
      )
    (Post, ["api", "handoffs", "requests"]) =>
      Some(
        @app_http.outbound_handoff_request_handler(self.handoff_outbox, request),
      )
    (Post, ["api", "handoffs", "receipt-references"]) =>
      Some(
        @app_http.outbound_handoff_receipt_reference_handler(
          self.handoff_outbox,
          request,
        ),
      )
    (Get, ["api", "handoffs", record_type, record_id]) =>
      Some(
        @app_http.outbound_handoff_record_handler(
          self.handoff_outbox,
          record_type,
          record_id,
        ),
      )
    (
      Post,
      [
        "api",
        "editor",
        "projects",
        project_id,
        "exports",
        job_id,
        "handoff-request",
      ],
    ) => {
      let input : EditorHandoffRequestInput = decode_body(request)
      Some(
        json_value_response(
          201,
          self.submit_editor_handoff_request(project_id, job_id, input),
        ),
      )
    }
    _ => None
  }
}

///|
pub fn StudioService::register_standard_application_routes(
  self : StudioService,
) -> Unit {
  for
    prefix in [
      "/api/provider-executions", "/api/v2/projects", "/api/commercial-intake", "/api/client",
      "/api/handoffs", "/api/editor",
    ] {
    self.register_route_extension(
      RouteExtension::new(prefix, async fn(request) {
        self.dispatch_application_http(request)
      }),
    )
  }
}
