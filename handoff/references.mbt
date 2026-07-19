///|
pub(all) struct RecordRef {
  record_id : String
  record_version : String
  record_digest : String
  provenance_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn exact_ref(reference : RecordRef, record : RecordRef) -> Bool {
  reference == record &&
  reference.record_id != "" &&
  reference.record_version != "" &&
  reference.record_digest != "" &&
  reference.provenance_ref != ""
}

///|
pub(all) struct HumanReview {
  reviewer_id : String
  reviewer_kind : String
  role : String
  authority_ref : String
  authorized : Bool
  evidence_refs : Array[String]
} derive(Debug, Eq, ToJson, FromJson)
