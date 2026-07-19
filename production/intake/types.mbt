///|
/// Exact MoonWiki-owned evidence identity. Mooncast copies this identity but
/// never rewrites the source knowledge record.
pub(all) struct MoonWikiEvidenceRef {
  source_id : String
  source_version : String
  source_digest : String
  provenance_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Stable MoonWiki intent records that downstream creative artifacts must
/// reference. They are supplied by the export packet; Mooncast never invents
/// fallback intent identifiers.
pub(all) struct CreativeIntentRefs {
  brief : MoonWikiEvidenceRef
  bible : MoonWikiEvidenceRef
  script : MoonWikiEvidenceRef
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClientNeed {
  customer : String
  payable_problem : String
  audience : String
  channels : Array[String]
  acceptance_method : String
  repeat_purchase_hypothesis : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ContractBoundary {
  contract_ref : String
  budget_ceiling_cny : Double
  revision_limit : Int
  target_duration_seconds : Int
  deliverables : Array[String]
  payment_milestones : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RightsAndProviderConstraints {
  rights_owner : String
  rights_confirmed : Bool
  rights_constraints : Array[String]
  confidentiality_class : String
  permitted_provider_ids : Array[String]
  prohibited_provider_ids : Array[String]
  permitted_data_class : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CreativeStrategy {
  project_title : String
  objective : String
  narrative_proposition : String
  tone : String
  claims : Array[String]
  success_metrics : Array[String]
  negative_constraints : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Domain-local import contract for a MoonWiki-exported packet. This is a
/// passive evidence port, not a MoonWiki API client or a second knowledge
/// store.
pub(all) struct MoonWikiNeedsPacket {
  contract : String
  packet_id : String
  packet_version : Int
  exported_at : String
  evidence_refs : Array[MoonWikiEvidenceRef]
  intent_refs : CreativeIntentRefs
  client_need : ClientNeed
  contract_boundary : ContractBoundary
  constraints : RightsAndProviderConstraints
  creative_strategy : CreativeStrategy
  unresolved_questions : Array[String]
  publication_authority : Bool
  provider_execution_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct IntakeValidation {
  contract : String
  complete : Bool
  errors : Array[String]
  unresolved_questions : Array[String]
  provenance_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ImportedIntake {
  contract : String
  packet : MoonWikiNeedsPacket
  validation : IntakeValidation
  imported_at : String
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct IntakeDecision {
  contract : String
  packet_id : String
  packet_version : Int
  provenance_digest : String
  decision : String
  actor : String
  actor_role : String
  note : String
  decided_at : String
  human_confirmed : Bool
  decision_digest : String
  publication_authority : Bool
  provider_execution_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProjectIntakeBinding {
  contract : String
  binding_id : String
  project_id : String
  project_revision : Int
  intake_id : String
  intake_version : Int
  intake_provenance_digest : String
  approval_digest : String
  brief_intent_ref : MoonWikiEvidenceRef
  bible_intent_ref : MoonWikiEvidenceRef
  script_intent_ref : MoonWikiEvidenceRef
  bound_at : String
  publication_authority : Bool
  provider_execution_authority : Bool
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct IntakeWorkspace {
  contract : String
  intakes : Array[ImportedIntake]
  decisions : Array[IntakeDecision]
  bindings : Array[ProjectIntakeBinding]
  publication_authority : Bool
  provider_execution_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)
