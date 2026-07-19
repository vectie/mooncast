///|
pub(all) struct Master {
  reference : @project.VersionRef
  duration_seconds : Int
  video_digest : String
  audio_digest : String
  subtitle_digest : String
  provenance_digest : String
  ai_label : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterDecision {
  master : @project.VersionRef
  kind : String
  decision : String
  actor : String
  role : String
  decided_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryPackage {
  reference : @project.VersionRef
  master : @project.VersionRef
  destination_ids : Array[String]
  manifest_digest : String
  rights_ledger_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryAcceptance {
  delivery_package : @project.VersionRef
  milestone : String
  decision : String
  actor : String
  decided_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PublicationAuthorization {
  delivery_package : @project.VersionRef
  destination_id : String
  decision : String
  actor : String
  decided_at : String
  external_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PublicationObservation {
  delivery_package : @project.VersionRef
  destination_id : String
  receipt_digest : String
  observed_at : String
  external_effect_performed_by_host : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PerformanceReview {
  delivery_package : @project.VersionRef
  status : String
  evidence_digest : String
  reach : Int
  completion_rate : Double
  conversion_rate : Double
  revenue_cny : Double
  provider_cost_cny : Double
  founder_hours : Double
  repeat_purchase_status : String
  actor : String
  reviewed_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn master_exact_approved(
  master : Master?,
  decisions : Array[MasterDecision],
) -> Bool {
  match master {
    None => false
    Some(current) => {
      let required = [
        "technical-qc", "creative-director", "rights-compliance", "client",
      ]
      required.all(kind => {
        decisions.any(decision => {
          decision.master == current.reference &&
          decision.kind == kind &&
          decision.decision == "approved" &&
          decision.actor != ""
        })
      })
    }
  }
}

///|
/// Internal master clearance is sufficient to prepare an exact review build.
/// Final G5 readiness still requires the separate named client decision.
pub fn master_internal_approved(
  master : Master?,
  decisions : Array[MasterDecision],
) -> Bool {
  match master {
    None => false
    Some(current) => {
      let required = ["technical-qc", "creative-director", "rights-compliance"]
      required.all(kind => {
        decisions.any(decision => {
          decision.master == current.reference &&
          decision.kind == kind &&
          decision.decision == "approved" &&
          decision.actor != ""
        })
      })
    }
  }
}

///|
pub fn delivery_exact_accepted(
  delivery : DeliveryPackage?,
  master : Master?,
  acceptances : Array[DeliveryAcceptance],
) -> Bool {
  match (delivery, master) {
    (Some(delivery), Some(current_master)) =>
      delivery.master == current_master.reference &&
      acceptances.any(acceptance => {
        acceptance.delivery_package == delivery.reference &&
        acceptance.decision == "accepted" &&
        acceptance.actor != ""
      })
    _ => false
  }
}

///|
pub fn publication_exact_authorized(
  delivery : DeliveryPackage?,
  authorizations : Array[PublicationAuthorization],
) -> Bool {
  match delivery {
    None => false
    Some(delivery) =>
      delivery.destination_ids.length() > 0 &&
      delivery.destination_ids.all(destination => {
        authorizations.any(authorization => {
          authorization.delivery_package == delivery.reference &&
          authorization.destination_id == destination &&
          authorization.decision == "authorized" &&
          authorization.actor != "" &&
          !authorization.external_effect_performed
        })
      })
  }
}

///|
pub fn performance_current(
  delivery : DeliveryPackage?,
  reviews : Array[PerformanceReview],
) -> Bool {
  match delivery {
    None => false
    Some(delivery) =>
      reviews.any(review => {
        review.delivery_package == delivery.reference &&
        review.actor != "" &&
        (
          review.status == "observed" ||
          (
            (review.status == "unavailable" || review.status == "waived") &&
            review.evidence_digest != ""
          )
        )
      })
  }
}

///|
pub fn master_record_valid(
  master : Master,
  target_duration_seconds : Int,
) -> Bool {
  master.reference.id != "" &&
  master.reference.version >= 1 &&
  master.reference.digest != "" &&
  master.duration_seconds >= target_duration_seconds - 1 &&
  master.duration_seconds <= target_duration_seconds + 2 &&
  master.video_digest != "" &&
  master.audio_digest != "" &&
  master.subtitle_digest != "" &&
  master.provenance_digest != "" &&
  master.ai_label != ""
}

///|
pub fn master_decision_valid(
  master : Master?,
  decision : MasterDecision,
) -> Bool {
  let kind_valid = decision.kind == "technical-qc" ||
    decision.kind == "creative-director" ||
    decision.kind == "rights-compliance" ||
    decision.kind == "client"
  match master {
    None => false
    Some(value) =>
      decision.master == value.reference &&
      kind_valid &&
      (
        decision.decision == "approved" ||
        decision.decision == "rejected" ||
        decision.decision == "revision-requested"
      ) &&
      decision.actor != "" &&
      decision.role != "" &&
      decision.decided_at != ""
  }
}

///|
pub fn delivery_package_valid(
  delivery : DeliveryPackage,
  master : Master?,
  master_decisions : Array[MasterDecision],
) -> Bool {
  delivery.reference.id != "" &&
  delivery.reference.version >= 1 &&
  delivery.reference.digest != "" &&
  delivery.destination_ids.length() > 0 &&
  delivery.manifest_digest != "" &&
  delivery.rights_ledger_digest != "" &&
  (match master {
    None => false
    Some(value) =>
      delivery.master == value.reference &&
      master_internal_approved(Some(value), master_decisions)
  })
}

///|
pub fn delivery_acceptance_valid(
  delivery : DeliveryPackage?,
  acceptance : DeliveryAcceptance,
) -> Bool {
  match delivery {
    None => false
    Some(value) =>
      acceptance.delivery_package == value.reference &&
      acceptance.milestone != "" &&
      acceptance.actor != "" &&
      acceptance.decided_at != "" &&
      (
        acceptance.decision == "accepted" ||
        acceptance.decision == "rejected" ||
        acceptance.decision == "revision-requested"
      )
  }
}

///|
pub fn publication_authorization_valid(
  delivery : DeliveryPackage?,
  authorization : PublicationAuthorization,
) -> Bool {
  match delivery {
    None => false
    Some(value) =>
      authorization.delivery_package == value.reference &&
      value.destination_ids.any(id => id == authorization.destination_id) &&
      (
        authorization.decision == "authorized" ||
        authorization.decision == "denied"
      ) &&
      authorization.actor != "" &&
      authorization.decided_at != "" &&
      !authorization.external_effect_performed
  }
}

///|
pub fn publication_observation_valid(
  delivery : DeliveryPackage?,
  authorizations : Array[PublicationAuthorization],
  observation : PublicationObservation,
) -> Bool {
  match delivery {
    None => false
    Some(value) =>
      observation.delivery_package == value.reference &&
      observation.receipt_digest != "" &&
      observation.observed_at != "" &&
      observation.external_effect_performed_by_host &&
      authorizations.any(authorization => {
        authorization.delivery_package == value.reference &&
        authorization.destination_id == observation.destination_id &&
        authorization.decision == "authorized"
      })
  }
}

///|
pub fn performance_review_valid(
  delivery : DeliveryPackage?,
  review : PerformanceReview,
) -> Bool {
  match delivery {
    None => false
    Some(value) =>
      review.delivery_package == value.reference &&
      review.actor != "" &&
      review.reviewed_at != "" &&
      review.reach >= 0 &&
      review.completion_rate >= 0.0 &&
      review.completion_rate <= 1.0 &&
      review.conversion_rate >= 0.0 &&
      review.conversion_rate <= 1.0 &&
      review.revenue_cny >= 0.0 &&
      review.provider_cost_cny >= 0.0 &&
      review.founder_hours >= 0.0 &&
      (
        review.status == "observed" ||
        review.status == "unavailable" ||
        review.status == "waived"
      ) &&
      (review.status == "observed" || review.evidence_digest != "")
  }
}
