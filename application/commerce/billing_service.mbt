///|
pub async fn CommercialApplicationService::transition_billing(
  self : CommercialApplicationService,
  billing_id : String,
  expected_revision : Int,
  state : String,
  actor : String,
  actor_role : String,
  reference : String,
  recorded_at : String,
  record_digest : String,
) -> @commerce_domain.MilestoneBillingEntry {
  let snapshot = self.load()
  let matches = snapshot.billing.filter(entry => entry.billing_id == billing_id)
  if matches.length() != 1 || matches[0].revision != expected_revision {
    raise CommercialCommandRejected("billing_revision_conflict")
  }
  let updated = match
    @commerce_domain.transition_billing(
      matches[0],
      state,
      actor,
      actor_role,
      reference,
      recorded_at,
      record_digest,
    ) {
    Some(value) => value
    None => raise CommercialCommandRejected("billing_transition_invalid")
  }
  let billing = snapshot.billing.filter(entry => entry.billing_id != billing_id)
  billing.push(updated)
  let revision = snapshot.revision + 1
  self.save({ ..snapshot, revision, billing })
  self.audit_action(
    "billing.state-recorded",
    @runtime.new_id(prefix="billing-state"),
    record_digest,
    recorded_at,
    revision,
  )
  updated
}

///|
pub async fn CommercialApplicationService::billing_for_project(
  self : CommercialApplicationService,
  project_id : String,
) -> Array[@commerce_domain.MilestoneBillingEntry] {
  let snapshot = self.load()
  snapshot.billing.filter(entry => entry.project_id == project_id)
}
