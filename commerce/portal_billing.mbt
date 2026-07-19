///|
pub(all) struct ClientBrand {
  name : String
  accent : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClientAnnotation {
  contract : String
  annotation_id : String
  portal_id : String
  master_sha256 : String
  build_digest : String
  timecode_seconds : Double
  body : String
  author : String
  created_at : String
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClientDecisionReceipt {
  contract : String
  portal_id : String
  decision : String
  master_sha256 : String
  build_digest : String
  governance_receipt_digest : String
  project_revision : Int
  decided_at : String
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClientPortal {
  contract : String
  portal_id : String
  project_id : String
  master_sha256 : String
  delivery_digest : String
  build_id : String
  build_digest : String
  client_name : String
  brand : ClientBrand
  scopes : Array[String]
  expires_at : String
  status : String
  revision : Int
  annotations : Array[ClientAnnotation]
  decisions : Array[ClientDecisionReceipt]
  created_by : String
  created_by_role : String
  created_at : String
  updated_at : String
  record_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BillingHistoryEntry {
  state : String
  actor : String
  actor_role : String
  reference : String
  recorded_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MilestoneBillingEntry {
  contract : String
  billing_id : String
  project_id : String
  kind : String
  currency : String
  amount : Double
  reference : String
  state : String
  quoted_at : String
  due_at : String?
  paid_at : String?
  waived_at : String?
  history : Array[BillingHistoryEntry]
  revision : Int
  record_digest : String
  payment_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RepeatOrderProposal {
  contract : String
  proposal_id : String
  source_project_id : String
  source_bible_digest : String
  source_build_digest : String
  new_project_id : String
  reusable_bible_digest : String
  reusable_asset_digests : Array[String]
  actor : String
  actor_role : String
  client_approval_carried : Bool
  publication_authority_carried : Bool
  created_at : String
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn portal_current(
  portal : ClientPortal,
  master_sha256 : String,
  delivery_digest : String,
  build : @execution.DeliveryBuild,
) -> Bool {
  portal.status == "active" &&
  portal.master_sha256 == master_sha256 &&
  portal.delivery_digest == delivery_digest &&
  portal.build_id == build.build_id &&
  portal.build_digest == build.build_digest &&
  build.state == "completed"
}

///|
pub fn append_annotation(
  portal : ClientPortal,
  annotation : ClientAnnotation,
  master_duration_seconds : Double,
  updated_at : String,
  record_digest : String,
) -> ClientPortal? {
  if portal.status != "active" ||
    annotation.portal_id != portal.portal_id ||
    annotation.master_sha256 != portal.master_sha256 ||
    annotation.build_digest != portal.build_digest ||
    annotation.timecode_seconds < 0.0 ||
    annotation.timecode_seconds > master_duration_seconds ||
    annotation.body == "" ||
    annotation.author == "" {
    return None
  }
  let annotations = portal.annotations.copy()
  annotations.push(annotation)
  Some({
    ..portal,
    annotations,
    revision: portal.revision + 1,
    updated_at,
    record_digest,
  })
}

///|
pub fn append_client_decision(
  portal : ClientPortal,
  decision : ClientDecisionReceipt,
  updated_at : String,
  record_digest : String,
) -> ClientPortal? {
  if portal.status != "active" ||
    portal.decisions.length() > 0 ||
    decision.portal_id != portal.portal_id ||
    decision.master_sha256 != portal.master_sha256 ||
    decision.build_digest != portal.build_digest ||
    (decision.decision != "accept" && decision.decision != "request-revision") {
    return None
  }
  let decisions = portal.decisions.copy()
  decisions.push(decision)
  Some({
    ..portal,
    decisions,
    status: if decision.decision == "request-revision" {
      "expired"
    } else {
      portal.status
    },
    revision: portal.revision + 1,
    updated_at,
    record_digest,
  })
}

///|
pub fn transition_billing(
  entry : MilestoneBillingEntry,
  state : String,
  actor : String,
  actor_role : String,
  reference : String,
  recorded_at : String,
  record_digest : String,
) -> MilestoneBillingEntry? {
  let allowed = match (entry.state, state) {
    ("quoted", "due") => true
    ("due", "paid") => true
    ("quoted", "waived") => true
    ("due", "waived") => true
    _ => false
  }
  if !allowed || actor == "" || actor_role == "" {
    return None
  }
  let history = entry.history.copy()
  history.push({ state, actor, actor_role, reference, recorded_at })
  Some({
    ..entry,
    state,
    due_at: if state == "due" {
      Some(recorded_at)
    } else {
      entry.due_at
    },
    paid_at: if state == "paid" {
      Some(recorded_at)
    } else {
      entry.paid_at
    },
    waived_at: if state == "waived" {
      Some(recorded_at)
    } else {
      entry.waived_at
    },
    history,
    revision: entry.revision + 1,
    record_digest,
    payment_effect_performed: false,
  })
}

///|
pub fn repeat_order_safe(proposal : RepeatOrderProposal) -> Bool {
  proposal.source_project_id != "" &&
  proposal.source_bible_digest != "" &&
  proposal.source_build_digest != "" &&
  proposal.new_project_id != "" &&
  proposal.actor != "" &&
  !proposal.client_approval_carried &&
  !proposal.publication_authority_carried
}
