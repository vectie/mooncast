///|
pub(all) struct QualifiedLead {
  contract : String
  lead : @project.VersionRef
  customer : String
  customer_contact_ref : String
  payable_problem : String
  baseline_cost_cny : Double
  baseline_time_hours : Double
  channels : Array[String]
  measurable_acceptance : Array[String]
  repeat_hypothesis : String
  status : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct LeadQualificationDecision {
  contract : String
  lead : @project.VersionRef
  decision : String
  actor : String
  actor_role : String
  note : String
  decided_at : String
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MarginForecast {
  contract : String
  quoted_revenue_cny : Double
  provider_cost_cny : Double
  labor_cost_cny : Double
  other_cost_cny : Double
  direct_cost_cny : Double
  contingency_cny : Double
  contribution_margin_cny : Double
  contribution_margin_rate : Double
  founder_hours : Double
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct QuoteMilestone {
  kind : String
  amount_cny : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct QuotedProject {
  project_id : String
  title : String
  objective : String
  audience : String
  rights_owner : String
  target_duration_seconds : Int
  production_budget_cny : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ScopedQuote {
  contract : String
  quote : @project.VersionRef
  source_lead : @project.VersionRef
  project : QuotedProject
  deliverables : Array[String]
  revision_rounds : Int
  provider_overage_policy : String
  milestones : Array[QuoteMilestone]
  rights_restrictions : Array[String]
  model_restrictions : Array[String]
  data_restrictions : Array[String]
  start_date : String
  delivery_date : String
  forecast : MarginForecast
  status : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct QuoteDecision {
  contract : String
  quote : @project.VersionRef
  authority : String
  decision : String
  actor : String
  actor_role : String
  note : String
  decided_at : String
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct QuoteConversion {
  contract : String
  quote : @project.VersionRef
  capacity_digest : String
  project_id : String
  actor : String
  actor_role : String
  converted_at : String
  digest : String
  payment_effect_performed : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn lead_is_qualified(
  lead : QualifiedLead,
  decisions : Array[LeadQualificationDecision],
) -> Bool {
  lead.status != "disqualified" &&
  decisions.any(decision => {
    decision.lead == lead.lead &&
    decision.decision == "qualify" &&
    decision.actor != "" &&
    decision.actor_role != ""
  })
}

///|
pub fn quote_is_internally_approved(
  quote : ScopedQuote,
  decisions : Array[QuoteDecision],
) -> Bool {
  ["commercial", "production"].all(authority => {
    decisions.any(decision => {
      decision.quote == quote.quote &&
      decision.authority == authority &&
      decision.decision == "approve" &&
      decision.actor != ""
    })
  }) &&
  !decisions.any(decision => {
    decision.quote == quote.quote && decision.decision == "reject"
  })
}

///|
pub fn quote_is_client_accepted(
  quote : ScopedQuote,
  decisions : Array[QuoteDecision],
) -> Bool {
  quote_is_internally_approved(quote, decisions) &&
  decisions.any(decision => {
    decision.quote == quote.quote &&
    decision.authority == "client" &&
    decision.decision == "accept" &&
    decision.actor != ""
  })
}

///|
pub fn quote_terms_valid(quote : ScopedQuote) -> Bool {
  let milestone_total = quote.milestones.fold(init=0.0, fn(total, milestone) {
    total + milestone.amount_cny
  })
  quote.project.target_duration_seconds >= 180 &&
  quote.project.target_duration_seconds <= 480 &&
  quote.project.production_budget_cny > 0.0 &&
  quote.project.production_budget_cny <= 5000.0 &&
  quote.revision_rounds >= 0 &&
  quote.revision_rounds <= 2 &&
  quote.deliverables.length() > 0 &&
  quote.milestones.length() == 3 &&
  quote.milestones.any(item => item.kind == "deposit") &&
  quote.milestones.any(item => item.kind == "animatic") &&
  quote.milestones.any(item => item.kind == "accepted-master") &&
  milestone_total == quote.forecast.quoted_revenue_cny &&
  quote.forecast.quoted_revenue_cny > 0.0 &&
  quote.forecast.direct_cost_cny >= 0.0 &&
  quote.forecast.founder_hours >= 0.0
}
