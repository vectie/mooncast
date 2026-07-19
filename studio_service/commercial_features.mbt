///|
struct LeadCreateInput {
  customer : String
  customer_contact_ref : String
  payable_problem : String
  baseline_cost_cny : Double
  baseline_time_hours : Double
  channels : Array[String]
  measurable_acceptance : Array[String]
  repeat_hypothesis : String
} derive(ToJson, FromJson)

///|
struct HumanDecisionInput {
  expected_version : Int
  expected_digest : String
  decision : String
  note : String
  human_confirmed : Bool
  actor : String
  actor_role : String
  authority : String?
} derive(FromJson)

///|
struct QuoteMilestoneInput {
  kind : String
  amount_cny : Double
} derive(ToJson, FromJson)

///|
struct QuoteInput {
  expected_lead_version : Int?
  expected_lead_digest : String?
  expected_version : Int?
  expected_digest : String?
  project_id : String
  title : String
  objective : String
  audience : String
  rights_owner : String
  target_duration_seconds : Int
  production_budget_cny : Double
  start_date : String
  delivery_date : String
  revision_rounds : Int
  deliverables : Array[String]
  provider_overage_policy : String
  rights_restrictions : Array[String]
  model_restrictions : Array[String]
  data_restrictions : Array[String]
  quoted_revenue_cny : Double
  provider_cost_cny : Double
  labor_cost_cny : Double
  other_cost_cny : Double
  founder_hours : Double
  contingency_percent : Double
  milestones : Array[QuoteMilestoneInput]
} derive(ToJson, FromJson)

///|
#warnings("-unused_field")
struct ResourceInput {
  name : String
  role : String
  skills : Array[String]
  weekly_hours : Double
  available_from : String
  available_to : String
  human_confirmed : Bool
  actor : String
  actor_role : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ReservationInput {
  quote_id : String
  quote_version : Int
  quote_digest : String
  resource_id : String
  skills : Array[String]
  depends_on : Array[String]
  start_date : String
  end_date : String
  hours : Double
  human_confirmed : Bool
  actor : String
  actor_role : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ReservationRescheduleInput {
  expected_revision : Int
  expected_digest : String
  start_date : String
  end_date : String
  hours : Double
  human_confirmed : Bool
  actor : String
  actor_role : String
} derive(FromJson)

///|
struct QuoteConversionInput {
  expected_version : Int
  expected_digest : String
  expected_capacity_digest : String
  human_confirmed : Bool
  actor : String
  actor_role : String
} derive(FromJson)

///|
struct RepeatOrderInput {
  expected_project_revision : Int
  expected_bible_digest : String
  expected_build_digest : String
  new_project_id : String
  title : String
  objective : String
  audience : String
  channels : Array[String]
  rights_owner : String
  rights_confirmed : Bool
  target_duration_seconds : Int
  max_budget_cny : Double
  reusable_asset_ids : Array[String]
  human_confirmed : Bool
  actor : String
  actor_role : String
} derive(FromJson)

///|
struct LeadProjection {
  contract : String
  lead_id : String
  version : Int
  digest : String
  customer : String
  customer_contact_ref : String
  payable_problem : String
  baseline_cost_cny : Double
  baseline_time_hours : Double
  channels : Array[String]
  measurable_acceptance : Array[String]
  repeat_hypothesis : String
  status : String
  qualification : Json?
} derive(ToJson)

///|
struct MarginScenarioProjection {
  name : String
  cost_multiplier : Double
  cost_cny : Double
  contribution_cny : Double
  contribution_rate : Double
} derive(ToJson)

///|
struct MarginProjection {
  quoted_revenue_cny : Double
  provider_cost_cny : Double
  labor_cost_cny : Double
  other_cost_cny : Double
  direct_cost_cny : Double
  gross_margin_cny : Double
  gross_margin_rate : Double
  contingency_cny : Double
  contribution_margin_cny : Double
  contribution_margin_rate : Double
  founder_hours : Double
  sensitivity : Array[MarginScenarioProjection]
  digest : String
} derive(ToJson)

///|
struct QuoteScheduleProjection {
  start_date : String
  delivery_date : String
} derive(ToJson)

///|
struct QuoteProjection {
  contract : String
  quote_id : String
  version : Int
  digest : String
  source_lead_id : String
  source_lead_version : Int
  source_lead_digest : String
  project : @commerce.QuotedProject
  deliverables : Array[String]
  revision_rounds : Int
  provider_overage_policy : String
  milestones : Array[@commerce.QuoteMilestone]
  restrictions : Json
  schedule : QuoteScheduleProjection
  forecast : MarginProjection
  status : String
  internal_approvals : Json
  client_acceptance : Json?
} derive(ToJson)

///|
struct ResourceProjection {
  contract : String
  resource_id : String
  version : Int
  digest : String
  name : String
  role : String
  skills : Array[String]
  weekly_hours : Double
  available_from : String
  available_to : String
} derive(ToJson)

///|
struct ReservationProjection {
  contract : String
  reservation_id : String
  revision : Int
  digest : String
  quote_id : String
  quote_version : Int
  quote_digest : String
  resource_id : String
  role : String
  skills : Array[String]
  start_date : String
  end_date : String
  hours : Double
  depends_on : Array[String]
  status : String
} derive(ToJson)

///|
struct ConversionProjection {
  contract : String
  quote_id : String
  quote_version : Int
  quote_digest : String
  capacity_digest : String
  project_id : String
  actor : String
  actor_role : String
  converted_at : String
  digest : String
  payment_effect_performed : Bool
  publication_authority : Bool
} derive(ToJson)

///|
struct CommercialDashboardProjection {
  contract : String
  revision : Int
  record_digest : String
  leads : Array[LeadProjection]
  quotes : Array[QuoteProjection]
  resources : Array[ResourceProjection]
  reservations : Array[ReservationProjection]
  conversions : Array[ConversionProjection]
  external_effects : Bool
} derive(ToJson)

///|
struct CapacityBoardProjection {
  contract : String
  quote_id : String
  quote_version : Int
  quote_digest : String
  reservations : Array[ReservationProjection]
  utilization : Array[Json]
  conflicts : Array[@commerce.CapacityConflict]
  ready : Bool
  calculated_at : String
  digest : String
} derive(ToJson)

///|
struct ConversionResultProjection {
  conversion : ConversionProjection
  project : Json
  external_effect_performed : Bool
  payment_effect_performed : Bool
  publication_authority : Bool
} derive(ToJson)

///|
struct RepeatOrderResultProjection {
  proposal : @commerce.RepeatOrderProposal
  project : Json
  client_approval_carried : Bool
  publication_authority_carried : Bool
  external_effect_performed : Bool
} derive(ToJson)

///|
fn latest_lead(
  snapshot : @commerce.CommercialSnapshot,
  lead_id : String,
) -> @commerce.QualifiedLead? {
  let candidates = snapshot.leads.filter(item => item.lead.id == lead_id)
  if candidates.is_empty() {
    return None
  }
  let mut latest = candidates[0]
  for item in candidates {
    if item.lead.version > latest.lead.version {
      latest = item
    }
  }
  Some(latest)
}

///|
fn latest_quote(
  snapshot : @commerce.CommercialSnapshot,
  quote_id : String,
) -> @commerce.ScopedQuote? {
  let candidates = snapshot.quotes.filter(item => item.quote.id == quote_id)
  if candidates.is_empty() {
    return None
  }
  let mut latest = candidates[0]
  for item in candidates {
    if item.quote.version > latest.quote.version {
      latest = item
    }
  }
  Some(latest)
}

///|
fn exact_resource(
  snapshot : @commerce.CommercialSnapshot,
  resource_id : String,
) -> @commerce.CapacityResource? {
  let candidates = snapshot.resources.filter(item => {
    item.resource.id == resource_id
  })
  if candidates.length() == 1 {
    Some(candidates[0])
  } else {
    None
  }
}

///|
fn exact_reservation(
  snapshot : @commerce.CommercialSnapshot,
  reservation_id : String,
) -> @commerce.CapacityReservation? {
  let candidates = snapshot.reservations.filter(item => {
    item.reservation.id == reservation_id
  })
  if candidates.length() == 1 {
    Some(candidates[0])
  } else {
    None
  }
}

///|
fn lead_projection(
  snapshot : @commerce.CommercialSnapshot,
  lead : @commerce.QualifiedLead,
) -> LeadProjection {
  let decisions = snapshot.lead_decisions.filter(item => item.lead == lead.lead)
  let decision = if decisions.is_empty() {
    None
  } else {
    Some(decisions[decisions.length() - 1])
  }
  {
    contract: lead.contract,
    lead_id: lead.lead.id,
    version: lead.lead.version,
    digest: lead.lead.digest,
    customer: lead.customer,
    customer_contact_ref: lead.customer_contact_ref,
    payable_problem: lead.payable_problem,
    baseline_cost_cny: lead.baseline_cost_cny,
    baseline_time_hours: lead.baseline_time_hours,
    channels: lead.channels,
    measurable_acceptance: lead.measurable_acceptance,
    repeat_hypothesis: lead.repeat_hypothesis,
    status: match decision {
      Some(value) =>
        if value.decision == "qualify" {
          "qualified"
        } else {
          "disqualified"
        }
      None => lead.status
    },
    qualification: decision.map(item => item.to_json()),
  }
}

///|
fn margin_projection(forecast : @commerce.MarginForecast) -> MarginProjection {
  let revenue = forecast.quoted_revenue_cny
  let gross = revenue - forecast.direct_cost_cny
  let scenarios : Array[MarginScenarioProjection] = []
  for scenario in [("favorable", 0.9), ("base", 1.0), ("adverse", 1.2)] {
    let (name, multiplier) = scenario
    let cost = forecast.direct_cost_cny * multiplier
    let contribution = revenue - cost - forecast.contingency_cny
    scenarios.push({
      name,
      cost_multiplier: multiplier,
      cost_cny: cost,
      contribution_cny: contribution,
      contribution_rate: if revenue == 0.0 {
        0.0
      } else {
        contribution / revenue
      },
    })
  }
  {
    quoted_revenue_cny: revenue,
    provider_cost_cny: forecast.provider_cost_cny,
    labor_cost_cny: forecast.labor_cost_cny,
    other_cost_cny: forecast.other_cost_cny,
    direct_cost_cny: forecast.direct_cost_cny,
    gross_margin_cny: gross,
    gross_margin_rate: if revenue == 0.0 {
      0.0
    } else {
      gross / revenue
    },
    contingency_cny: forecast.contingency_cny,
    contribution_margin_cny: forecast.contribution_margin_cny,
    contribution_margin_rate: forecast.contribution_margin_rate,
    founder_hours: forecast.founder_hours,
    sensitivity: scenarios,
    digest: forecast.digest,
  }
}

///|
fn quote_projection(
  snapshot : @commerce.CommercialSnapshot,
  quote : @commerce.ScopedQuote,
) -> QuoteProjection {
  let decisions = snapshot.quote_decisions.filter(item => {
    item.quote == quote.quote
  })
  let commercial = decisions
    .iter()
    .find_first(item => item.authority == "commercial")
  let production = decisions
    .iter()
    .find_first(item => item.authority == "production")
  let client = decisions.iter().find_first(item => item.authority == "client")
  let approvals : Map[String, Json] = {}
  match commercial {
    Some(value) => approvals["commercial"] = value.to_json()
    None => ()
  }
  match production {
    Some(value) => approvals["production"] = value.to_json()
    None => ()
  }
  let status = match client {
    Some(value) if value.decision == "accept" => "accepted"
    Some(value) if value.decision == "reject" => "rejected"
    _ =>
      if commercial is Some(_) && production is Some(_) {
        "internally-approved"
      } else {
        quote.status
      }
  }
  {
    contract: quote.contract,
    quote_id: quote.quote.id,
    version: quote.quote.version,
    digest: quote.quote.digest,
    source_lead_id: quote.source_lead.id,
    source_lead_version: quote.source_lead.version,
    source_lead_digest: quote.source_lead.digest,
    project: quote.project,
    deliverables: quote.deliverables,
    revision_rounds: quote.revision_rounds,
    provider_overage_policy: quote.provider_overage_policy,
    milestones: quote.milestones,
    restrictions: Json::object({
      "rights": quote.rights_restrictions.to_json(),
      "models": quote.model_restrictions.to_json(),
      "data": quote.data_restrictions.to_json(),
    }),
    schedule: {
      start_date: quote.start_date,
      delivery_date: quote.delivery_date,
    },
    forecast: margin_projection(quote.forecast),
    status,
    internal_approvals: Json::object(approvals),
    client_acceptance: client.map(item => item.to_json()),
  }
}

///|
fn resource_projection(
  resource : @commerce.CapacityResource,
) -> ResourceProjection {
  {
    contract: resource.contract,
    resource_id: resource.resource.id,
    version: resource.resource.version,
    digest: resource.resource.digest,
    name: resource.name,
    role: resource.role,
    skills: resource.skills,
    weekly_hours: resource.weekly_hours,
    available_from: resource.available_from,
    available_to: resource.available_to,
  }
}

///|
fn reservation_projection(
  reservation : @commerce.CapacityReservation,
) -> ReservationProjection {
  {
    contract: reservation.contract,
    reservation_id: reservation.reservation.id,
    revision: reservation.reservation.version,
    digest: reservation.reservation.digest,
    quote_id: reservation.quote.id,
    quote_version: reservation.quote.version,
    quote_digest: reservation.quote.digest,
    resource_id: reservation.resource.id,
    role: reservation.role,
    skills: reservation.skills,
    start_date: reservation.start_date,
    end_date: reservation.end_date,
    hours: reservation.hours,
    depends_on: reservation.depends_on,
    status: reservation.status,
  }
}

///|
fn conversion_projection(
  conversion : @commerce.QuoteConversion,
) -> ConversionProjection {
  {
    contract: conversion.contract,
    quote_id: conversion.quote.id,
    quote_version: conversion.quote.version,
    quote_digest: conversion.quote.digest,
    capacity_digest: conversion.capacity_digest,
    project_id: conversion.project_id,
    actor: conversion.actor,
    actor_role: conversion.actor_role,
    converted_at: conversion.converted_at,
    digest: conversion.digest,
    payment_effect_performed: false,
    publication_authority: false,
  }
}

///|
pub async fn StudioService::commercial_dashboard_projection(
  self : StudioService,
) -> CommercialDashboardProjection {
  let snapshot = self.commerce_application.load()
  let leads : Array[LeadProjection] = []
  for item in snapshot.leads {
    if latest_lead(snapshot, item.lead.id) == Some(item) {
      leads.push(lead_projection(snapshot, item))
    }
  }
  let quotes : Array[QuoteProjection] = []
  for item in snapshot.quotes {
    if latest_quote(snapshot, item.quote.id) == Some(item) {
      quotes.push(quote_projection(snapshot, item))
    }
  }
  {
    contract: "mooncast.commercial-intake-dashboard.v1",
    revision: snapshot.revision,
    record_digest: "sha256:" + sha256_text(snapshot.to_json().stringify()),
    leads,
    quotes,
    resources: snapshot.resources.map(resource_projection),
    reservations: snapshot.reservations.map(reservation_projection),
    conversions: snapshot.conversions.map(conversion_projection),
    external_effects: false,
  }
}

///|
pub async fn StudioService::commercial_lead_projection(
  self : StudioService,
  lead_id : String,
) -> LeadProjection {
  let snapshot = self.commerce_application.load()
  guard latest_lead(snapshot, lead_id) is Some(lead) else {
    fail("lead does not exist")
  }
  lead_projection(snapshot, lead)
}

///|
pub async fn StudioService::commercial_quote_projection(
  self : StudioService,
  quote_id : String,
) -> QuoteProjection {
  let snapshot = self.commerce_application.load()
  guard latest_quote(snapshot, quote_id) is Some(quote) else {
    fail("quote does not exist")
  }
  quote_projection(snapshot, quote)
}

///|
pub async fn StudioService::create_commercial_lead(
  self : StudioService,
  input : LeadCreateInput,
) -> LeadProjection {
  let snapshot = self.commerce_application.load()
  let lead_id = @runtime.new_id(prefix="lead")
  let digest = "sha256:" +
    sha256_text(input.to_json().stringify() + ":" + lead_id)
  let lead : @commerce.QualifiedLead = {
    contract: "mooncast.qualified-lead.v1",
    lead: { id: lead_id, version: 1, digest },
    customer: input.customer,
    customer_contact_ref: input.customer_contact_ref,
    payable_problem: input.payable_problem,
    baseline_cost_cny: input.baseline_cost_cny,
    baseline_time_hours: input.baseline_time_hours,
    channels: input.channels,
    measurable_acceptance: input.measurable_acceptance,
    repeat_hypothesis: input.repeat_hypothesis,
    status: "draft",
  }
  let result = self.commerce_application.submit(
    commercial_command(snapshot, "record_lead", digest, lead~),
  )
  lead_projection(result.snapshot, lead)
}

///|
pub async fn StudioService::qualify_commercial_lead(
  self : StudioService,
  lead_id : String,
  input : HumanDecisionInput,
) -> LeadProjection {
  guard input.human_confirmed else {
    fail("named human confirmation is required")
  }
  let snapshot = self.commerce_application.load()
  guard latest_lead(snapshot, lead_id) is Some(lead) &&
    lead.lead.version == input.expected_version &&
    normalized_digest(lead.lead.digest) ==
    normalized_digest(input.expected_digest) else {
    fail("lead binding changed")
  }
  let decided_at = now_string()
  let digest = "sha256:" +
    sha256_text(
      lead.lead.digest +
      ":" +
      input.decision +
      ":" +
      input.actor +
      ":" +
      input.note,
    )
  let decision : @commerce.LeadQualificationDecision = {
    contract: "mooncast.lead-qualification-decision.v1",
    lead: lead.lead,
    decision: input.decision,
    actor: input.actor,
    actor_role: input.actor_role,
    note: input.note,
    decided_at,
    digest,
  }
  let result = self.commerce_application.submit(
    commercial_command(
      snapshot,
      "record_lead_decision",
      digest,
      lead_decision=decision,
    ),
  )
  lead_projection(result.snapshot, lead)
}

///|
fn quote_forecast(input : QuoteInput) -> @commerce.MarginForecast {
  let direct = input.provider_cost_cny +
    input.labor_cost_cny +
    input.other_cost_cny
  let contingency = direct * input.contingency_percent / 100.0
  let contribution = input.quoted_revenue_cny - direct - contingency
  let digest = "sha256:" +
    sha256_text(
      input.quoted_revenue_cny.to_string() +
      ":" +
      direct.to_string() +
      ":" +
      contingency.to_string(),
    )
  {
    contract: "mooncast.margin-forecast.v1",
    quoted_revenue_cny: input.quoted_revenue_cny,
    provider_cost_cny: input.provider_cost_cny,
    labor_cost_cny: input.labor_cost_cny,
    other_cost_cny: input.other_cost_cny,
    direct_cost_cny: direct,
    contingency_cny: contingency,
    contribution_margin_cny: contribution,
    contribution_margin_rate: if input.quoted_revenue_cny == 0.0 {
      0.0
    } else {
      contribution / input.quoted_revenue_cny
    },
    founder_hours: input.founder_hours,
    digest,
  }
}

///|
pub async fn StudioService::create_or_revise_quote(
  self : StudioService,
  lead_id : String,
  quote_id : String?,
  input : QuoteInput,
) -> QuoteProjection {
  let snapshot = self.commerce_application.load()
  guard latest_lead(snapshot, lead_id) is Some(lead) else {
    fail("lead does not exist")
  }
  let (id, version) = match quote_id {
    None => {
      guard input.expected_lead_version == Some(lead.lead.version) &&
        input.expected_lead_digest.map(normalized_digest) ==
        Some(normalized_digest(lead.lead.digest)) else {
        fail("lead binding changed")
      }
      (@runtime.new_id(prefix="quote"), 1)
    }
    Some(id) => {
      guard latest_quote(snapshot, id) is Some(previous) &&
        input.expected_version == Some(previous.quote.version) &&
        input.expected_digest.map(normalized_digest) ==
        Some(normalized_digest(previous.quote.digest)) else {
        fail("quote binding changed")
      }
      (id, previous.quote.version + 1)
    }
  }
  let digest = "sha256:" +
    sha256_text(
      id + ":" + version.to_string() + ":" + input.to_json().stringify(),
    )
  let quote : @commerce.ScopedQuote = {
    contract: "mooncast.scoped-quote.v1",
    quote: { id, version, digest },
    source_lead: lead.lead,
    project: {
      project_id: input.project_id,
      title: input.title,
      objective: input.objective,
      audience: input.audience,
      rights_owner: input.rights_owner,
      target_duration_seconds: input.target_duration_seconds,
      production_budget_cny: input.production_budget_cny,
    },
    deliverables: input.deliverables,
    revision_rounds: input.revision_rounds,
    provider_overage_policy: input.provider_overage_policy,
    milestones: input.milestones.map(item => @commerce.QuoteMilestone::{
      kind: item.kind,
      amount_cny: item.amount_cny,
    }),
    rights_restrictions: input.rights_restrictions,
    model_restrictions: input.model_restrictions,
    data_restrictions: input.data_restrictions,
    start_date: input.start_date,
    delivery_date: input.delivery_date,
    forecast: quote_forecast(input),
    status: "draft",
  }
  let result = self.commerce_application.submit(
    commercial_command(snapshot, "record_quote", digest, quote~),
  )
  quote_projection(result.snapshot, quote)
}

///|
pub async fn StudioService::decide_commercial_quote(
  self : StudioService,
  quote_id : String,
  authority : String,
  input : HumanDecisionInput,
) -> QuoteProjection {
  guard input.human_confirmed else {
    fail("named human confirmation is required")
  }
  let snapshot = self.commerce_application.load()
  guard latest_quote(snapshot, quote_id) is Some(quote) &&
    quote.quote.version == input.expected_version &&
    normalized_digest(quote.quote.digest) ==
    normalized_digest(input.expected_digest) else {
    fail("quote binding changed")
  }
  let digest = "sha256:" +
    sha256_text(
      quote.quote.digest +
      ":" +
      authority +
      ":" +
      input.decision +
      ":" +
      input.actor,
    )
  let decision : @commerce.QuoteDecision = {
    contract: "mooncast.quote-decision.v1",
    quote: quote.quote,
    authority,
    decision: input.decision,
    actor: input.actor,
    actor_role: input.actor_role,
    note: input.note,
    decided_at: now_string(),
    digest,
  }
  let result = self.commerce_application.submit(
    commercial_command(
      snapshot,
      "record_quote_decision",
      digest,
      quote_decision=decision,
    ),
  )
  quote_projection(result.snapshot, quote)
}

///|
pub async fn StudioService::create_capacity_resource(
  self : StudioService,
  input : ResourceInput,
) -> ResourceProjection {
  guard input.human_confirmed else {
    fail("named human confirmation is required")
  }
  let snapshot = self.commerce_application.load()
  let id = @runtime.new_id(prefix="resource")
  let digest = "sha256:" + sha256_text(id + ":" + input.name + ":" + input.role)
  let resource : @commerce.CapacityResource = {
    contract: "mooncast.capacity-resource.v1",
    resource: { id, version: 1, digest },
    name: input.name,
    role: input.role,
    skills: input.skills,
    weekly_hours: input.weekly_hours,
    available_from: input.available_from,
    available_to: input.available_to,
  }
  ignore(
    self.commerce_application.submit(
      commercial_command(
        snapshot,
        "record_capacity_resource",
        digest,
        resource~,
      ),
    ),
  )
  resource_projection(resource)
}

///|
async fn StudioService::record_capacity_board(
  self : StudioService,
  quote : @commerce.ScopedQuote,
) -> CapacityBoardProjection {
  let snapshot = self.commerce_application.load()
  let calculated_at = now_string()
  let digest = "sha256:" +
    sha256_text(
      quote.quote.digest +
      ":" +
      snapshot.reservations.to_json().stringify() +
      ":" +
      calculated_at,
    )
  let board = @commerce.calculate_capacity(
    quote,
    snapshot.resources,
    snapshot.reservations,
    calculated_at,
    digest,
  )
  let result = self.commerce_application.submit(
    commercial_command(
      snapshot,
      "record_capacity_board",
      digest,
      capacity_board=board,
    ),
  )
  let exact = result.snapshot.reservations.filter(item => {
    item.quote == quote.quote
  })
  {
    contract: board.contract,
    quote_id: quote.quote.id,
    quote_version: quote.quote.version,
    quote_digest: quote.quote.digest,
    reservations: exact.map(reservation_projection),
    utilization: [],
    conflicts: board.conflicts,
    ready: board.ready,
    calculated_at: board.calculated_at,
    digest: board.digest,
  }
}

///|
pub async fn StudioService::create_capacity_reservation(
  self : StudioService,
  input : ReservationInput,
) -> ReservationProjection {
  guard input.human_confirmed else {
    fail("named human confirmation is required")
  }
  let snapshot = self.commerce_application.load()
  guard latest_quote(snapshot, input.quote_id) is Some(quote) &&
    quote.quote.version == input.quote_version &&
    normalized_digest(quote.quote.digest) ==
    normalized_digest(input.quote_digest) &&
    exact_resource(snapshot, input.resource_id) is Some(resource) else {
    fail("quote or resource binding changed")
  }
  let id = @runtime.new_id(prefix="reservation")
  let digest = "sha256:" +
    sha256_text(
      id +
      ":" +
      quote.quote.digest +
      ":" +
      resource.resource.digest +
      ":" +
      input.start_date +
      ":" +
      input.end_date,
    )
  let reservation : @commerce.CapacityReservation = {
    contract: "mooncast.capacity-reservation.v1",
    reservation: { id, version: 1, digest },
    quote: quote.quote,
    resource: resource.resource,
    role: resource.role,
    skills: input.skills,
    start_date: input.start_date,
    end_date: input.end_date,
    hours: input.hours,
    depends_on: input.depends_on,
    status: "reserved",
  }
  ignore(
    self.commerce_application.submit(
      commercial_command(
        snapshot,
        "record_capacity_reservation",
        digest,
        reservation~,
      ),
    ),
  )
  ignore(self.record_capacity_board(quote))
  reservation_projection(reservation)
}

///|
pub async fn StudioService::reschedule_capacity_reservation(
  self : StudioService,
  reservation_id : String,
  input : ReservationRescheduleInput,
) -> ReservationProjection {
  guard input.human_confirmed else {
    fail("named human confirmation is required")
  }
  let snapshot = self.commerce_application.load()
  guard exact_reservation(snapshot, reservation_id) is Some(previous) &&
    previous.reservation.version == input.expected_revision &&
    normalized_digest(previous.reservation.digest) ==
    normalized_digest(input.expected_digest) else {
    fail("reservation binding changed")
  }
  let digest = "sha256:" +
    sha256_text(
      previous.reservation.digest +
      ":" +
      input.start_date +
      ":" +
      input.end_date +
      ":" +
      input.hours.to_string(),
    )
  let updated = {
    ..previous,
    reservation: {
      ..previous.reservation,
      version: previous.reservation.version + 1,
      digest,
    },
    start_date: input.start_date,
    end_date: input.end_date,
    hours: input.hours,
  }
  let saved = self.commerce_application.reschedule_reservation(
    previous, updated,
  )
  let refreshed = self.commerce_application.load()
  guard latest_quote(refreshed, previous.quote.id) is Some(quote) else {
    fail("quote does not exist")
  }
  ignore(self.record_capacity_board(quote))
  reservation_projection(saved)
}

///|
pub async fn StudioService::capacity_board_projection(
  self : StudioService,
  quote_id : String,
) -> CapacityBoardProjection {
  let snapshot = self.commerce_application.load()
  guard latest_quote(snapshot, quote_id) is Some(quote) else {
    fail("quote does not exist")
  }
  match self.commerce_application.capacity_board(quote_id~) {
    Some(board) => {
      let exact = snapshot.reservations.filter(item => item.quote == quote.quote)
      {
        contract: board.contract,
        quote_id,
        quote_version: quote.quote.version,
        quote_digest: quote.quote.digest,
        reservations: exact.map(reservation_projection),
        utilization: [],
        conflicts: board.conflicts,
        ready: board.ready,
        calculated_at: board.calculated_at,
        digest: board.digest,
      }
    }
    None => {
      let calculated_at = now_string()
      let digest = "sha256:" +
        sha256_text(
          quote.quote.digest + ":" + snapshot.reservations.to_json().stringify(),
        )
      let board = @commerce.calculate_capacity(
        quote,
        snapshot.resources,
        snapshot.reservations,
        calculated_at,
        digest,
      )
      {
        contract: board.contract,
        quote_id,
        quote_version: quote.quote.version,
        quote_digest: quote.quote.digest,
        reservations: snapshot.reservations
        .filter(item => item.quote == quote.quote)
        .map(reservation_projection),
        utilization: [],
        conflicts: board.conflicts,
        ready: board.ready,
        calculated_at,
        digest,
      }
    }
  }
}

///|
pub async fn StudioService::convert_commercial_quote(
  self : StudioService,
  quote_id : String,
  input : QuoteConversionInput,
) -> ConversionResultProjection {
  guard input.human_confirmed else {
    fail("named human confirmation is required")
  }
  let snapshot = self.commerce_application.load()
  guard latest_quote(snapshot, quote_id) is Some(quote) &&
    quote.quote.version == input.expected_version &&
    normalized_digest(quote.quote.digest) ==
    normalized_digest(input.expected_digest) &&
    self.commerce_application.capacity_board(quote_id~) is Some(board) &&
    board.ready &&
    normalized_digest(board.digest) ==
    normalized_digest(input.expected_capacity_digest) else {
    fail("accepted quote or capacity binding changed")
  }
  let converted_at = now_string()
  let digest = "sha256:" +
    sha256_text(
      quote.quote.digest +
      ":" +
      board.digest +
      ":" +
      quote.project.project_id +
      ":" +
      input.actor,
    )
  let conversion : @commerce.QuoteConversion = {
    contract: "mooncast.quote-conversion.v1",
    quote: quote.quote,
    capacity_digest: board.digest,
    project_id: quote.project.project_id,
    actor: input.actor,
    actor_role: input.actor_role,
    converted_at,
    digest,
    payment_effect_performed: false,
    publication_authority: false,
  }
  ignore(
    self.commerce_application.submit(
      commercial_command(snapshot, "convert_quote", digest, conversion~),
    ),
  )
  let graph = @production_app.episode_production_graph(
    quote.project.project_id,
    quote.project.title,
    quote.project.target_duration_seconds,
    quote.project.production_budget_cny,
  )
  let project = self.create_project(graph, converted_at)
  let experience : ProjectExperienceMetadata = {
    objective: quote.project.objective,
    audience: quote.project.audience,
    channels: ["review-only"],
    rights_owner: quote.project.rights_owner,
    rights_confirmed: true,
  }
  self.save_project_experience(project.project_id, experience)
  let ready = self.seed_initial_creative_drafts(
    project.project_id,
    experience,
    converted_at,
  )
  {
    conversion: conversion_projection(conversion),
    project: self.studio_project_projection(ready),
    external_effect_performed: false,
    payment_effect_performed: false,
    publication_authority: false,
  }
}

///|
pub async fn StudioService::create_repeat_order(
  self : StudioService,
  source_project_id : String,
  input : RepeatOrderInput,
) -> RepeatOrderResultProjection {
  guard input.human_confirmed &&
    input.rights_confirmed &&
    input.actor != "" &&
    input.actor_role != "" else {
    fail("named human and rights confirmation are required")
  }
  let source = self.get_project(source_project_id)
  guard source.snapshot.revision == input.expected_project_revision else {
    fail("source project changed")
  }
  let bibles = source.snapshot.creative_artifacts.filter(item => {
    item.kind == @creative.IpBible
  })
  guard !bibles.is_empty() &&
    normalized_digest(bibles[bibles.length() - 1].reference.digest) ==
    normalized_digest(input.expected_bible_digest) else {
    fail("repeat order must bind the exact approved IP bible")
  }
  let builds = self.delivery_application
    .list(source_project_id)
    .filter(build => {
      normalized_digest(build.build_digest) ==
      normalized_digest(input.expected_build_digest) &&
      build.state == "completed"
    })
  guard builds.length() == 1 &&
    self.delivery_application.acceptance(builds[0].build_id) is Some(acceptance) &&
    acceptance.acceptance.decision == "accept" else {
    fail("repeat order must bind an accepted customer delivery build")
  }
  let reusable = source.snapshot.graph.assets.filter(asset => {
    input.reusable_asset_ids.contains(asset.asset_id)
  })
  let created_at = now_string()
  let digest = "sha256:" +
    sha256_text(
      source_project_id +
      ":" +
      input.new_project_id +
      ":" +
      input.expected_bible_digest +
      ":" +
      input.expected_build_digest +
      ":" +
      input.actor,
    )
  let proposal : @commerce.RepeatOrderProposal = {
    contract: "mooncast.repeat-order-proposal.v1",
    proposal_id: @runtime.new_id(prefix="repeat-order"),
    source_project_id,
    source_bible_digest: normalized_digest(input.expected_bible_digest),
    source_build_digest: normalized_digest(input.expected_build_digest),
    new_project_id: input.new_project_id,
    reusable_bible_digest: normalized_digest(input.expected_bible_digest),
    reusable_asset_digests: reusable.map(asset => asset.digest),
    actor: input.actor,
    actor_role: input.actor_role,
    client_approval_carried: false,
    publication_authority_carried: false,
    created_at,
    digest,
  }
  let commercial = self.commerce_application.load()
  ignore(
    self.commerce_application.submit(
      commercial_command(
        commercial,
        "record_repeat_order",
        digest,
        repeat_order=proposal,
      ),
    ),
  )
  let reusable_asset_ids = reusable.map(asset => asset.asset_id)
  let base_graph = @production_app.episode_production_graph(
    input.new_project_id,
    input.title,
    input.target_duration_seconds,
    input.max_budget_cny,
  )
  let graph : @project.ProjectGraph = {
    ..base_graph,
    episodes: base_graph.episodes.map(episode => {
      ..episode,
      scenes: episode.scenes.map(scene => {
        ..scene,
        shots: scene.shots.map(shot => {
          ..shot,
          source_asset_ids: reusable_asset_ids,
        }),
      }),
    }),
    assets: reusable,
  }
  let created = self.create_project(graph, created_at)
  let experience : ProjectExperienceMetadata = {
    objective: input.objective,
    audience: input.audience,
    channels: input.channels,
    rights_owner: input.rights_owner,
    rights_confirmed: input.rights_confirmed,
  }
  self.save_project_experience(created.project_id, experience)
  let ready = self.seed_initial_creative_drafts(
    created.project_id,
    experience,
    created_at,
  )
  {
    proposal,
    project: self.studio_project_projection(ready),
    client_approval_carried: false,
    publication_authority_carried: false,
    external_effect_performed: false,
  }
}
