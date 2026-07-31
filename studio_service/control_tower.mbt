///|
struct ControlTowerActualsInput {
  command_id : String
  expected_project_revision : Int
  expected_actuals_version : Int?
  expected_actuals_digest : String?
  provider_cost_confirmed_cny : Double?
  labor_cost_cny : Double?
  other_cost_cny : Double?
  recognized_revenue_cny : Double?
  founder_hours : Double?
  completed_labor_hours : Double?
  forecast_completion_date : String?
  provider_cost_reconciled : Bool
  evidence_refs : Array[String]
  actor : String
  actor_role : String
  observed_at : String
  human_confirmed : Bool
} derive(ToJson, FromJson)

///|
struct ControlTowerAssignmentInput {
  command_id : String
  expected_exception_digest : String
  expected_assignment_version : Int?
  expected_assignment_digest : String?
  owner : String
  owner_role : String
  action_due_date : String
  note : String
  assigned_by : String
  assigned_by_role : String
  assigned_at : String
  human_confirmed : Bool
} derive(ToJson, FromJson)

///|
struct ProjectCommercialBinding {
  conversion : @commerce.QuoteConversion
  quote : @commerce.ScopedQuote
}

///|
struct PortfolioReservation {
  reservation : @commerce.CapacityReservation
  resource : @commerce.CapacityResource?
  project_id : String
}

///|
fn control_tower_actuals_key(project_id : String) -> String {
  "control-tower-actuals-" + project_id + ".json"
}

///|
fn control_tower_assignment_key(exception_id : String) -> String {
  "control-tower-assignment-" + exception_id + ".json"
}

///|
fn control_tower_query_value(query : String?, name : String) -> String? {
  guard query is Some(query) else { return None }
  for component in query.split("&") {
    let pair = component.split("=").to_array()
    if pair.length() == 2 && pair[0].to_owned() == name {
      return Some(pair[1].to_owned())
    }
  }
  None
}

///|
fn control_tower_today() -> String {
  @moonlib_os.local_date_key(@runtime.wall_clock_ms() / 1000L)
}

///|
fn tower_digest(value : String) -> String {
  "sha256:" + sha256_text(value)
}

///|
fn double_nonnegative(value : Double?) -> Bool {
  value.map(item => item >= 0.0).unwrap_or(true)
}

///|
fn current_project_binding(
  commercial : @commerce.CommercialSnapshot,
  project_id : String,
) -> ProjectCommercialBinding? {
  let conversions = commercial.conversions.filter(item => {
    item.project_id == project_id
  })
  if conversions.is_empty() {
    return None
  }
  let conversion = conversions[conversions.length() - 1]
  let quotes = commercial.quotes.filter(item => item.quote == conversion.quote)
  if quotes.length() == 1 {
    Some({ conversion, quote: quotes[0] })
  } else {
    None
  }
}

///|
fn reservations_overlap(
  first : @commerce.CapacityReservation,
  second : @commerce.CapacityReservation,
) -> Bool {
  first.start_date <= second.end_date && second.start_date <= first.end_date
}

///|
fn overlap_start(
  first : @commerce.CapacityReservation,
  second : @commerce.CapacityReservation,
) -> String {
  if first.start_date >= second.start_date {
    first.start_date
  } else {
    second.start_date
  }
}

///|
fn overlap_end(
  first : @commerce.CapacityReservation,
  second : @commerce.CapacityReservation,
) -> String {
  if first.end_date <= second.end_date {
    first.end_date
  } else {
    second.end_date
  }
}

///|
fn resource_for_reservation(
  commercial : @commerce.CommercialSnapshot,
  reservation : @commerce.CapacityReservation,
) -> @commerce.CapacityResource? {
  let matches = commercial.resources.filter(item => {
    item.resource == reservation.resource
  })
  if matches.length() == 1 {
    Some(matches[0])
  } else {
    None
  }
}

///|
fn portfolio_reservations(
  commercial : @commerce.CommercialSnapshot,
) -> Array[PortfolioReservation] {
  let values : Array[PortfolioReservation] = []
  for reservation in commercial.reservations {
    if reservation.status != "reserved" {
      continue
    }
    let conversions = commercial.conversions.filter(item => {
      item.quote == reservation.quote
    })
    if conversions.length() == 1 {
      values.push({
        reservation,
        resource: resource_for_reservation(commercial, reservation),
        project_id: conversions[0].project_id,
      })
    }
  }
  values
}

///|
fn reallocation_candidates(
  commercial : @commerce.CommercialSnapshot,
  reservations : Array[PortfolioReservation],
  first : PortfolioReservation,
  second : PortfolioReservation,
) -> Array[@control_tower.ReallocationCandidate] {
  let required_hours = Double::min(
    first.reservation.hours,
    second.reservation.hours,
  )
  let required_skills = first.reservation.skills
  let start = overlap_start(first.reservation, second.reservation)
  let end = overlap_end(first.reservation, second.reservation)
  let candidates : Array[@control_tower.ReallocationCandidate] = []
  for candidate in commercial.resources {
    if candidate.resource == first.reservation.resource ||
      candidate.role != first.reservation.role ||
      candidate.available_from > start ||
      candidate.available_to < end ||
      !required_skills.all(skill => candidate.skills.contains(skill)) {
      continue
    }
    let mut occupied = 0.0
    for current in reservations {
      if current.reservation.resource == candidate.resource &&
        current.reservation.start_date <= end &&
        start <= current.reservation.end_date {
        occupied = occupied + current.reservation.hours
      }
    }
    let available = Double::max(0.0, candidate.weekly_hours - occupied)
    if available >= required_hours {
      candidates.push({
        resource_id: candidate.resource.id,
        resource_name: candidate.name,
        role: candidate.role,
        available_hours: available,
        matched_skills: required_skills,
      })
    }
  }
  candidates
}

///|
fn portfolio_capacity_conflicts(
  commercial : @commerce.CommercialSnapshot,
) -> Array[@control_tower.CapacityConflict] {
  let reservations = portfolio_reservations(commercial)
  let conflicts : Array[@control_tower.CapacityConflict] = []
  for first_index in 0..<reservations.length() {
    for second_index in (first_index + 1)..<reservations.length() {
      let first = reservations[first_index]
      let second = reservations[second_index]
      if first.reservation.resource != second.reservation.resource ||
        !reservations_overlap(first.reservation, second.reservation) {
        continue
      }
      guard first.resource is Some(resource) else { continue }
      let total = first.reservation.hours + second.reservation.hours
      if total <= resource.weekly_hours {
        continue
      }
      let ordered_ids = [
        first.reservation.reservation.id,
        second.reservation.reservation.id,
      ]
      ordered_ids.sort()
      let core = resource.resource.digest +
        ":" +
        ordered_ids.join(":") +
        ":" +
        overlap_start(first.reservation, second.reservation) +
        ":" +
        overlap_end(first.reservation, second.reservation) +
        ":" +
        total.to_string()
      let digest = tower_digest(core)
      let suffix = digest[7:31].to_owned()
      conflicts.push({
        conflict_id: "capacity-conflict-" + suffix,
        exception_id: "exception-capacity-" + suffix,
        resource_id: resource.resource.id,
        resource_name: resource.name,
        role: resource.role,
        reservation_ids: ordered_ids,
        project_ids: [first.project_id, second.project_id],
        overlap_start: overlap_start(first.reservation, second.reservation),
        overlap_end: overlap_end(first.reservation, second.reservation),
        reserved_hours: total,
        weekly_hours: resource.weekly_hours,
        overbooked_hours: total - resource.weekly_hours,
        reallocation_candidates: reallocation_candidates(
          commercial, reservations, first, second,
        ),
        digest,
      })
    }
  }
  conflicts
}

///|
async fn StudioService::control_tower_actuals(
  self : StudioService,
  project_id : String,
) -> @control_tower.OperatingActuals? {
  load_value(self.store, control_tower_actuals_key(project_id))
}

///|
async fn StudioService::control_tower_assignment(
  self : StudioService,
  exception_id : String,
) -> @control_tower.ExceptionAssignment? {
  load_value(self.store, control_tower_assignment_key(exception_id))
}

///|
fn actuals_equal_input(
  current : @control_tower.OperatingActuals,
  input : ControlTowerActualsInput,
) -> Bool {
  current.command_id == input.command_id &&
  current.project_revision == input.expected_project_revision &&
  current.provider_cost_confirmed_cny == input.provider_cost_confirmed_cny &&
  current.labor_cost_cny == input.labor_cost_cny &&
  current.other_cost_cny == input.other_cost_cny &&
  current.recognized_revenue_cny == input.recognized_revenue_cny &&
  current.founder_hours == input.founder_hours &&
  current.completed_labor_hours == input.completed_labor_hours &&
  current.forecast_completion_date == input.forecast_completion_date &&
  current.provider_cost_reconciled == input.provider_cost_reconciled &&
  current.evidence_refs == input.evidence_refs &&
  current.actor == input.actor &&
  current.actor_role == input.actor_role &&
  current.observed_at == input.observed_at
}

///|
async fn StudioService::record_control_tower_actuals(
  self : StudioService,
  project_id : String,
  input : ControlTowerActualsInput,
) -> @control_tower.OperatingActuals {
  guard input.human_confirmed &&
    valid_id(input.command_id) &&
    input.actor.trim() != "" &&
    input.actor_role.trim() != "" &&
    input.observed_at.trim() != "" &&
    !input.evidence_refs.is_empty() &&
    input.evidence_refs.all(value => value.trim() != "") &&
    double_nonnegative(input.provider_cost_confirmed_cny) &&
    double_nonnegative(input.labor_cost_cny) &&
    double_nonnegative(input.other_cost_cny) &&
    double_nonnegative(input.recognized_revenue_cny) &&
    double_nonnegative(input.founder_hours) &&
    double_nonnegative(input.completed_labor_hours) &&
    (
      !input.provider_cost_reconciled ||
      input.provider_cost_confirmed_cny is Some(_)
    ) &&
    input.forecast_completion_date
    .map(value => @control_tower.iso_date_ordinal(value) is Some(_))
    .unwrap_or(true) else {
    raise Invalid(
      code="control_tower_actuals_invalid",
      message="actuals require named evidence, non-negative values, and a valid forecast date",
    )
  }
  let project = self.get_project(project_id)
  guard project.snapshot.revision == input.expected_project_revision else {
    raise Conflict(
      code="control_tower_project_revision_conflict",
      message="operating actuals must bind the exact canonical project revision",
    )
  }
  let current = self.control_tower_actuals(project_id)
  match current {
    Some(value) if value.command_id == input.command_id =>
      if actuals_equal_input(value, input) {
        return value
      } else {
        raise Conflict(
          code="control_tower_idempotency_conflict",
          message="command id is already bound to different operating actuals",
        )
      }
    _ => ()
  }
  let version = match current {
    None => {
      guard input.expected_actuals_version is None &&
        input.expected_actuals_digest is None else {
        raise Conflict(
          code="control_tower_actuals_conflict",
          message="no previous operating actuals exist",
        )
      }
      1
    }
    Some(previous) => {
      guard input.expected_actuals_version == Some(previous.version) &&
        input.expected_actuals_digest.map(normalized_digest) ==
        Some(normalized_digest(previous.digest)) else {
        raise Conflict(
          code="control_tower_actuals_conflict",
          message="operating actuals changed before this update",
        )
      }
      previous.version + 1
    }
  }
  let core : @control_tower.OperatingActuals = {
    contract: "mooncast.control-tower-operating-actuals.v1",
    command_id: input.command_id,
    project_id,
    version,
    project_revision: input.expected_project_revision,
    provider_cost_confirmed_cny: input.provider_cost_confirmed_cny,
    labor_cost_cny: input.labor_cost_cny,
    other_cost_cny: input.other_cost_cny,
    recognized_revenue_cny: input.recognized_revenue_cny,
    founder_hours: input.founder_hours,
    completed_labor_hours: input.completed_labor_hours,
    forecast_completion_date: input.forecast_completion_date,
    provider_cost_reconciled: input.provider_cost_reconciled,
    evidence_refs: input.evidence_refs,
    actor: input.actor,
    actor_role: input.actor_role,
    observed_at: input.observed_at,
    digest: "",
  }
  let record = { ..core, digest: tower_digest(core.to_json().stringify()) }
  save_value(self.store, control_tower_actuals_key(project_id), record)
  record
}

///|
fn assignment_equal_input(
  current : @control_tower.ExceptionAssignment,
  input : ControlTowerAssignmentInput,
) -> Bool {
  current.command_id == input.command_id &&
  normalized_digest(current.exception_digest) ==
  normalized_digest(input.expected_exception_digest) &&
  current.owner == input.owner &&
  current.owner_role == input.owner_role &&
  current.action_due_date == input.action_due_date &&
  current.note == input.note &&
  current.assigned_by == input.assigned_by &&
  current.assigned_by_role == input.assigned_by_role &&
  current.assigned_at == input.assigned_at
}

///|
async fn StudioService::assign_control_tower_exception(
  self : StudioService,
  exception_id : String,
  input : ControlTowerAssignmentInput,
) -> @control_tower.ExceptionAssignment {
  guard input.human_confirmed &&
    valid_id(input.command_id) &&
    input.owner.trim() != "" &&
    input.owner_role.trim() != "" &&
    input.assigned_by.trim() != "" &&
    input.assigned_by_role.trim() != "" &&
    input.assigned_at.trim() != "" &&
    @control_tower.iso_date_ordinal(input.action_due_date) is Some(_) else {
    raise Invalid(
      code="control_tower_assignment_invalid",
      message="assignment requires named people, confirmation, and a valid due date",
    )
  }
  let tower = self.production_control_tower()
  let matches = tower.exceptions.filter(item => {
    item.exception_id == exception_id &&
    normalized_digest(item.digest) ==
    normalized_digest(input.expected_exception_digest)
  })
  guard matches.length() == 1 else {
    raise Conflict(
      code="control_tower_exception_conflict",
      message="exception changed or no longer exists",
    )
  }
  let current = self.control_tower_assignment(exception_id)
  match current {
    Some(value) if value.command_id == input.command_id =>
      if assignment_equal_input(value, input) {
        return value
      } else {
        raise Conflict(
          code="control_tower_idempotency_conflict",
          message="command id is already bound to a different assignment",
        )
      }
    _ => ()
  }
  let version = match current {
    None => {
      guard input.expected_assignment_version is None &&
        input.expected_assignment_digest is None else {
        raise Conflict(
          code="control_tower_assignment_conflict",
          message="no previous assignment exists",
        )
      }
      1
    }
    Some(previous) => {
      guard input.expected_assignment_version == Some(previous.version) &&
        input.expected_assignment_digest.map(normalized_digest) ==
        Some(normalized_digest(previous.digest)) else {
        raise Conflict(
          code="control_tower_assignment_conflict",
          message="exception ownership changed before this assignment",
        )
      }
      previous.version + 1
    }
  }
  let core : @control_tower.ExceptionAssignment = {
    contract: "mooncast.control-tower-exception-assignment.v1",
    command_id: input.command_id,
    exception_id,
    exception_digest: normalized_digest(input.expected_exception_digest),
    version,
    owner: input.owner,
    owner_role: input.owner_role,
    action_due_date: input.action_due_date,
    note: input.note,
    assigned_by: input.assigned_by,
    assigned_by_role: input.assigned_by_role,
    assigned_at: input.assigned_at,
    human_confirmed: true,
    external_effect_authorized: false,
    digest: "",
  }
  let assignment = { ..core, digest: tower_digest(core.to_json().stringify()) }
  save_value(self.store, control_tower_assignment_key(exception_id), assignment)
  assignment
}

///|
fn spend_plan(binding : ProjectCommercialBinding?) -> @control_tower.SpendPlan? {
  binding.map(value => {
    let forecast = value.quote.forecast
    {
      provider_cny: forecast.provider_cost_cny,
      labor_cny: forecast.labor_cost_cny,
      other_cny: forecast.other_cost_cny,
      direct_cny: forecast.direct_cost_cny,
      contingency_cny: forecast.contingency_cny,
      revenue_cny: forecast.quoted_revenue_cny,
      gross_margin_cny: forecast.quoted_revenue_cny - forecast.direct_cost_cny,
      contribution_margin_cny: forecast.contribution_margin_cny,
      founder_hours: forecast.founder_hours,
    }
  })
}

///|
fn make_tower_exception(
  project_id : String?,
  kind : String,
  severity : String,
  summary : String,
  evidence_refs : Array[String],
) -> @control_tower.ControlTowerException {
  let core = project_id.unwrap_or("portfolio") +
    ":" +
    kind +
    ":" +
    severity +
    ":" +
    summary +
    ":" +
    evidence_refs.join(":")
  let digest = tower_digest(core)
  {
    exception_id: "exception-" + digest[7:31].to_owned(),
    project_id,
    kind,
    severity,
    summary,
    evidence_refs,
    digest,
    assignment: None,
  }
}

///|
async fn StudioService::bind_exception_assignment(
  self : StudioService,
  exception : @control_tower.ControlTowerException,
) -> @control_tower.ControlTowerException {
  match self.control_tower_assignment(exception.exception_id) {
    Some(assignment) if normalized_digest(assignment.exception_digest) ==
      normalized_digest(exception.digest) =>
      { ..exception, assignment: Some(assignment) }
    _ => exception
  }
}

///|
fn project_revision_rounds(
  commercial : @commerce.CommercialSnapshot,
  project_id : String,
  included : Int?,
) -> @control_tower.RevisionBurden {
  let used = commercial.portals
    .filter(portal => portal.project_id == project_id)
    .fold(init=0, (total, portal) => {
      total +
      portal.decisions
      .filter(decision => decision.decision == "request-revision")
      .length()
    })
  @control_tower.revision_burden(included, used)
}

///|
async fn StudioService::project_provider_cost(
  self : StudioService,
  snapshot : @kernel.ProjectSnapshot,
  actuals : @control_tower.OperatingActuals?,
) -> @control_tower.ProviderCostBreakdown {
  let asset_factory = self.asset_factory.workspace(snapshot.graph.project_id)
  let animatic = self.animatic.workspace(snapshot.graph.project_id)
  let postprocess = self.postprocess.workspace(snapshot.graph.project_id)
  let automated_qc = self.automated_qc.workspace(snapshot.graph.project_id)
  let generation = snapshot.generation_attempts.fold(init=0.0, (sum, value) => {
    sum + value.cost_cny
  })
  let animatic_cost = animatic.renders.fold(init=0.0, (sum, value) => {
    sum + value.budget.actual_cny
  })
  @control_tower.provider_cost_breakdown(
    generation,
    asset_factory.total_spent_cny,
    animatic_cost,
    postprocess.total_cost_cny,
    automated_qc.total_cost_cny,
    actuals,
  )
}

///|
fn project_missing_evidence(
  binding : ProjectCommercialBinding?,
  snapshot : @kernel.ProjectSnapshot,
  actuals : @control_tower.OperatingActuals?,
  provider : @control_tower.ProviderCostBreakdown,
  remaining : @control_tower.RemainingWork,
) -> Array[String] {
  let missing : Array[String] = []
  if binding is None {
    missing.push("accepted_quote_and_conversion")
  }
  match actuals {
    None => {
      missing.push("operating_actuals")
      missing.push("labor_cost_actual")
      missing.push("other_cost_actual")
      missing.push("recognized_revenue_actual")
      missing.push("founder_hours_actual")
      if remaining.completion_rate < 1.0 {
        missing.push("completion_forecast")
      }
    }
    Some(value) => {
      if value.project_revision != snapshot.revision {
        missing.push("operating_actuals_current_project_revision")
      }
      if value.labor_cost_cny is None {
        missing.push("labor_cost_actual")
      }
      if value.other_cost_cny is None {
        missing.push("other_cost_actual")
      }
      if value.recognized_revenue_cny is None {
        missing.push("recognized_revenue_actual")
      }
      if value.founder_hours is None {
        missing.push("founder_hours_actual")
      }
      if remaining.completion_rate < 1.0 &&
        value.forecast_completion_date is None {
        missing.push("completion_forecast")
      }
    }
  }
  if provider.evidence_state != "evidence-reconciled" {
    missing.push("provider_cost_reconciliation")
  }
  if !@governance.delivery_exact_accepted(
      snapshot.delivery_package,
      snapshot.master,
      snapshot.delivery_acceptances,
    ) {
    missing.push("accepted_master_minutes")
  }
  missing
}

///|
fn project_accepted_minutes(snapshot : @kernel.ProjectSnapshot) -> Double? {
  if @governance.delivery_exact_accepted(
      snapshot.delivery_package,
      snapshot.master,
      snapshot.delivery_acceptances,
    ) {
    snapshot.master.map(value => value.duration_seconds.to_double() / 60.0)
  } else {
    None
  }
}

///|
fn project_base_exceptions(
  project_id : String,
  plan : @control_tower.SpendPlan?,
  actual : @control_tower.SpendActual,
  schedule : @control_tower.ScheduleHealth,
  revisions : @control_tower.RevisionBurden,
  missing : Array[String],
) -> Array[@control_tower.ControlTowerException] {
  let exceptions : Array[@control_tower.ControlTowerException] = []
  if !missing.is_empty() {
    exceptions.push(
      make_tower_exception(
        Some(project_id),
        "missing-evidence",
        "attention",
        missing.length().to_string() +
        " operating evidence fields are incomplete",
        missing,
      ),
    )
  }
  if schedule.risk == "at-risk" ||
    schedule.risk == "high" ||
    schedule.risk == "breached" {
    exceptions.push(
      make_tower_exception(
        Some(project_id),
        "delivery-sla",
        if schedule.risk == "breached" {
          "critical"
        } else {
          "high"
        },
        "Delivery SLA is " + schedule.risk,
        schedule.basis,
      ),
    )
  }
  match (plan, actual.direct_cny) {
    (Some(plan), Some(actual_direct)) if actual_direct > plan.direct_cny =>
      exceptions.push(
        make_tower_exception(
          Some(project_id),
          "direct-cost-overrun",
          "high",
          "Actual direct cost exceeds the accepted quote plan by CNY " +
          (actual_direct - plan.direct_cny).to_string(),
          ["control-tower-operating-actuals", "accepted-scoped-quote"],
        ),
      )
    _ => ()
  }
  if revisions.state == "overage" {
    exceptions.push(
      make_tower_exception(
        Some(project_id),
        "revision-overage",
        "high",
        "Client revision requests exceed the included quote policy",
        ["client-portal-decisions", "accepted-scoped-quote"],
      ),
    )
  }
  if actual.provider.discrepancy_cny
    .map(value => Double::abs(value) > 0.01)
    .unwrap_or(false) {
    exceptions.push(
      make_tower_exception(
        Some(project_id),
        "provider-cost-conflict",
        "attention",
        "Confirmed provider cost differs from canonical operation records",
        ["provider-operation-records", "control-tower-operating-actuals"],
      ),
    )
  }
  exceptions
}

///|
async fn StudioService::build_project_control(
  self : StudioService,
  record : ProjectRecord,
  commercial : @commerce.CommercialSnapshot,
  conflicts : Array[@control_tower.CapacityConflict],
  as_of_date : String,
) -> (
  @control_tower.ProjectControl,
  Array[@control_tower.ControlTowerException],
) {
  let snapshot = record.snapshot
  let project_id = record.project_id
  let binding = current_project_binding(commercial, project_id)
  let plan = spend_plan(binding)
  let actuals = self.control_tower_actuals(project_id)
  let provider = self.project_provider_cost(snapshot, actuals)
  let actual = @control_tower.spend_actual(provider, actuals)
  let remaining = @control_tower.remaining_work(snapshot)
  let conflict_ids = conflicts
    .filter(value => value.project_ids.contains(project_id))
    .map(value => value.conflict_id)
  let schedule = @control_tower.schedule_health(
    as_of_date,
    binding.map(value => value.quote.start_date),
    binding.map(value => value.quote.delivery_date),
    match actuals {
      Some(value) => value.forecast_completion_date
      None => None
    },
    remaining,
    !conflict_ids.is_empty(),
  )
  let revisions = project_revision_rounds(
    commercial,
    project_id,
    binding.map(value => value.quote.revision_rounds),
  )
  let accepted_minutes = project_accepted_minutes(snapshot)
  let missing = project_missing_evidence(
    binding, snapshot, actuals, provider, remaining,
  )
  let exceptions = project_base_exceptions(
    project_id, plan, actual, schedule, revisions, missing,
  )
  let capacity_exception_ids = conflicts
    .filter(value => value.project_ids.contains(project_id))
    .map(value => value.exception_id)
  let exception_ids = [
    ..exceptions.map(value => value.exception_id),
    ..capacity_exception_ids,
  ]
  let projection = @kernel.projection(snapshot)
  let accepted_cost = match (accepted_minutes, actual.direct_cny) {
    (Some(minutes), Some(cost)) if minutes > 0.0 => Some(cost / minutes)
    _ => None
  }
  let core : @control_tower.ProjectControl = {
    contract: "mooncast.project-control-tower.v1",
    project_id,
    project_revision: snapshot.revision,
    title: snapshot.graph.title,
    stage: projection.stage,
    current_gate: projection.current_gate,
    quote_id: binding.map(value => value.quote.quote.id),
    quote_version: binding.map(value => value.quote.quote.version),
    quote_digest: binding.map(value => value.quote.quote.digest),
    actuals_version: actuals.map(value => value.version),
    actuals_digest: actuals.map(value => value.digest),
    actuals_observed_at: actuals.map(value => value.observed_at),
    actuals_evidence_refs: actuals
    .map(value => value.evidence_refs)
    .unwrap_or([]),
    planned: plan,
    actual,
    variance: @control_tower.spend_variance(plan, actual),
    schedule,
    remaining,
    revisions,
    accepted_minutes,
    cost_per_accepted_minute_cny: accepted_cost,
    capacity_conflict_ids: conflict_ids,
    exception_ids,
    missing_evidence: missing,
    digest: "",
  }
  ({ ..core, digest: tower_digest(core.to_json().stringify()) }, exceptions)
}

///|
fn optional_total_add(current : Double?, value : Double?) -> Double? {
  match (current, value) {
    (Some(current), Some(value)) => Some(current + value)
    _ => None
  }
}

///|
fn portfolio_totals(
  projects : Array[@control_tower.ProjectControl],
  exceptions : Array[@control_tower.ControlTowerException],
) -> @control_tower.PortfolioTotals {
  let mut accepted_quotes = 0
  let mut planned_revenue = 0.0
  let mut planned_direct = 0.0
  let mut planned_contribution = 0.0
  let mut planned_founder = 0.0
  let mut actual_provider = 0.0
  let mut actual_labor : Double? = Some(0.0)
  let mut actual_other : Double? = Some(0.0)
  let mut actual_revenue : Double? = Some(0.0)
  let mut actual_gross : Double? = Some(0.0)
  let mut actual_contribution : Double? = Some(0.0)
  let mut actual_founder : Double? = Some(0.0)
  let mut sla_risk = 0
  for project in projects {
    match project.planned {
      Some(plan) => {
        accepted_quotes = accepted_quotes + 1
        planned_revenue = planned_revenue + plan.revenue_cny
        planned_direct = planned_direct + plan.direct_cny
        planned_contribution = planned_contribution +
          plan.contribution_margin_cny
        planned_founder = planned_founder + plan.founder_hours
      }
      None => ()
    }
    actual_provider = actual_provider +
      project.actual.provider.confirmed_total_cny.unwrap_or(
        project.actual.provider.operational_total_cny,
      )
    actual_labor = optional_total_add(actual_labor, project.actual.labor_cny)
    actual_other = optional_total_add(actual_other, project.actual.other_cny)
    actual_revenue = optional_total_add(
      actual_revenue,
      project.actual.revenue_cny,
    )
    actual_gross = optional_total_add(
      actual_gross,
      project.actual.gross_margin_cny,
    )
    actual_contribution = optional_total_add(
      actual_contribution,
      project.actual.contribution_margin_cny,
    )
    actual_founder = optional_total_add(
      actual_founder,
      project.actual.founder_hours,
    )
    if project.schedule.risk == "at-risk" ||
      project.schedule.risk == "high" ||
      project.schedule.risk == "breached" {
      sla_risk = sla_risk + 1
    }
  }
  {
    project_count: projects.length(),
    projects_with_accepted_quotes: accepted_quotes,
    planned_revenue_cny: planned_revenue,
    planned_direct_cost_cny: planned_direct,
    planned_contribution_margin_cny: planned_contribution,
    actual_provider_cost_cny: actual_provider,
    actual_labor_cost_cny: actual_labor,
    actual_other_cost_cny: actual_other,
    actual_revenue_cny: actual_revenue,
    actual_gross_margin_cny: actual_gross,
    actual_contribution_margin_cny: actual_contribution,
    planned_founder_hours: planned_founder,
    actual_founder_hours: actual_founder,
    projects_at_sla_risk: sla_risk,
    open_exception_count: exceptions.length(),
    unowned_exception_count: exceptions
    .filter(value => value.assignment is None)
    .length(),
  }
}

///|
pub async fn StudioService::production_control_tower(
  self : StudioService,
  as_of_date? : String = control_tower_today(),
) -> @control_tower.ControlTower {
  guard @control_tower.iso_date_ordinal(as_of_date) is Some(_) else {
    raise Invalid(
      code="control_tower_date_invalid",
      message="as_of_date must be an exact YYYY-MM-DD date",
    )
  }
  let commercial = self.commerce_application.load()
  let conflicts = portfolio_capacity_conflicts(commercial)
  let projects : Array[@control_tower.ProjectControl] = []
  let raw_exceptions : Array[@control_tower.ControlTowerException] = []
  for summary in self.list_projects() {
    let record = self.get_project(summary.project_id)
    let (project, exceptions) = self.build_project_control(
      record, commercial, conflicts, as_of_date,
    )
    projects.push(project)
    for exception in exceptions {
      raw_exceptions.push(exception)
    }
  }
  for conflict in conflicts {
    raw_exceptions.push({
      exception_id: conflict.exception_id,
      project_id: None,
      kind: "capacity-conflict",
      severity: "high",
      summary: conflict.resource_name +
      " is overbooked by " +
      conflict.overbooked_hours.to_string() +
      " hours",
      evidence_refs: conflict.reservation_ids,
      digest: conflict.digest,
      assignment: None,
    })
  }
  let exceptions : Array[@control_tower.ControlTowerException] = []
  for exception in raw_exceptions {
    exceptions.push(self.bind_exception_assignment(exception))
  }
  let missing : Array[String] = []
  if projects.any(value => !value.missing_evidence.is_empty()) {
    missing.push("project_operating_evidence_incomplete")
  }
  if projects.any(value => value.planned is None) {
    missing.push("portfolio_contains_unquoted_projects")
  }
  if conflicts.any(value => value.reallocation_candidates.is_empty()) {
    missing.push("capacity_conflict_without_reallocation_candidate")
  }
  let core : @control_tower.ControlTower = {
    contract: "mooncast.production-control-tower.v1",
    pack_id: "mooncast",
    pack_version: "0.2.0",
    as_of_date,
    projects,
    capacity_conflicts: conflicts,
    exceptions,
    totals: portfolio_totals(projects, exceptions),
    missing_evidence: missing,
    publication_authority: false,
    payment_effect_performed: false,
    external_effect_authorized: false,
    digest: "",
  }
  { ..core, digest: tower_digest(core.to_json().stringify()) }
}

///|
fn zero_pad(value : Int, width : Int) -> String {
  let text = value.to_string()
  if text.length() >= width {
    text
  } else {
    "0".repeat(width - text.length()) + text
  }
}

///|
fn utc_timestamp_from_seconds(seconds : Int64) -> String {
  let days = (seconds / 86400L).to_int()
  let day_seconds = (seconds % 86400L).to_int()
  let shifted = days + 719468
  let era = if shifted >= 0 {
    shifted / 146097
  } else {
    (shifted - 146096) / 146097
  }
  let day_of_era = shifted - era * 146097
  let year_of_era = (
      day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096
    ) /
    365
  let mut year = year_of_era + era * 400
  let day_of_year = day_of_era -
    (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
  let shifted_month = (5 * day_of_year + 2) / 153
  let day = day_of_year - (153 * shifted_month + 2) / 5 + 1
  let month = shifted_month + (if shifted_month < 10 { 3 } else { -9 })
  if month <= 2 {
    year = year + 1
  }
  let hour = day_seconds / 3600
  let minute = day_seconds % 3600 / 60
  let second = day_seconds % 60
  zero_pad(year, 4) +
  "-" +
  zero_pad(month, 2) +
  "-" +
  zero_pad(day, 2) +
  "T" +
  zero_pad(hour, 2) +
  ":" +
  zero_pad(minute, 2) +
  ":" +
  zero_pad(second, 2) +
  "Z"
}

///|
fn control_tower_adapter_declaration() -> Json {
  moonflow_adapter_declaration()
}

///|
async fn StudioService::control_tower_adapter_health_evidence(
  self : StudioService,
) -> Json {
  self.moonflow_adapter_health_evidence()
}

///|
async fn StudioService::control_tower_adapter_health(
  self : StudioService,
) -> Json {
  self.moonflow_adapter_health()
}

///|
async fn StudioService::dispatch_control_tower_http(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response? {
  let segments = path_segments(request.path)
  match (request.request_method, segments) {
    (Get, ["api", "control-tower"]) => {
      let as_of = control_tower_query_value(request.query, "as_of_date")
      Some(
        json_value_response(
          200,
          match as_of {
            Some(value) => self.production_control_tower(as_of_date=value)
            None => self.production_control_tower()
          },
        ),
      )
    }
    (Get, ["api", "control-tower", "projects", project_id, "actuals"]) =>
      match self.control_tower_actuals(project_id) {
        Some(value) => Some(json_value_response(200, value))
        None =>
          Some(
            api_error(
              404, "control_tower_actuals_not_found", "operating actuals have not been recorded",
            ),
          )
      }
    (Post, ["api", "control-tower", "projects", project_id, "actuals"]) => {
      let input : ControlTowerActualsInput = decode_body(request)
      Some(
        json_value_response(
          201,
          self.record_control_tower_actuals(project_id, input),
        ),
      )
    }
    (Get, ["api", "control-tower", "exceptions", exception_id, "assignment"]) =>
      match self.control_tower_assignment(exception_id) {
        Some(value) => Some(json_value_response(200, value))
        None =>
          Some(
            api_error(
              404, "control_tower_assignment_not_found", "exception has no named owner",
            ),
          )
      }
    (Post, ["api", "control-tower", "exceptions", exception_id, "assignment"]) => {
      let input : ControlTowerAssignmentInput = decode_body(request)
      Some(
        json_value_response(
          201,
          self.assign_control_tower_exception(exception_id, input),
        ),
      )
    }
    (Get, ["api", "control-tower", "adapter", "declaration"]) =>
      Some(json_value_response(200, control_tower_adapter_declaration()))
    (Get, ["api", "control-tower", "adapter", "health"]) =>
      Some(json_value_response(200, self.control_tower_adapter_health()))
    (Get, ["api", "control-tower", "adapter", "health", "evidence"]) =>
      Some(
        json_value_response(200, self.control_tower_adapter_health_evidence()),
      )
    _ => None
  }
}

///|
pub fn StudioService::register_control_tower_routes(
  self : StudioService,
) -> Unit {
  self.register_route_extension(
    RouteExtension::new("/api/control-tower", async fn(request) {
      self.dispatch_control_tower_http(request)
    }),
  )
}
