///|
fn event_from(command : CommercialCommand, kind : String) -> CommercialEvent {
  {
    contract: "mooncast.commercial-event.v1",
    event_id: command.command_id,
    kind,
    recorded_at: command.recorded_at,
    evidence_digest: command.evidence_digest,
    lead: command.lead,
    lead_decision: command.lead_decision,
    quote: command.quote,
    quote_decision: command.quote_decision,
    resource: command.resource,
    reservation: command.reservation,
    capacity_board: command.capacity_board,
    conversion: command.conversion,
    portal: command.portal,
    billing: command.billing,
    repeat_order: command.repeat_order,
  }
}

///|
pub fn apply_commercial_event(
  snapshot : CommercialSnapshot,
  event : CommercialEvent,
) -> CommercialSnapshot {
  let next = match event.kind {
    "lead-recorded" =>
      match event.lead {
        Some(value) => {
          let items = snapshot.leads.copy()
          items.push(value)
          { ..snapshot, leads: items }
        }
        None => snapshot
      }
    "lead-decision-recorded" =>
      match event.lead_decision {
        Some(value) => {
          let items = snapshot.lead_decisions.copy()
          items.push(value)
          { ..snapshot, lead_decisions: items }
        }
        None => snapshot
      }
    "quote-recorded" =>
      match event.quote {
        Some(value) => {
          let items = snapshot.quotes.copy()
          items.push(value)
          { ..snapshot, quotes: items }
        }
        None => snapshot
      }
    "quote-decision-recorded" =>
      match event.quote_decision {
        Some(value) => {
          let items = snapshot.quote_decisions.copy()
          items.push(value)
          { ..snapshot, quote_decisions: items }
        }
        None => snapshot
      }
    "capacity-resource-recorded" =>
      match event.resource {
        Some(value) => {
          let items = snapshot.resources.copy()
          items.push(value)
          { ..snapshot, resources: items }
        }
        None => snapshot
      }
    "capacity-reservation-recorded" =>
      match event.reservation {
        Some(value) => {
          let items = snapshot.reservations.copy()
          items.push(value)
          { ..snapshot, reservations: items }
        }
        None => snapshot
      }
    "capacity-board-recorded" =>
      match event.capacity_board {
        Some(value) => {
          let items = snapshot.capacity_boards.copy()
          items.push(value)
          { ..snapshot, capacity_boards: items }
        }
        None => snapshot
      }
    "quote-converted" =>
      match event.conversion {
        Some(value) => {
          let items = snapshot.conversions.copy()
          items.push(value)
          { ..snapshot, conversions: items }
        }
        None => snapshot
      }
    "client-portal-recorded" =>
      match event.portal {
        Some(value) => {
          let items = snapshot.portals.copy()
          items.push(value)
          { ..snapshot, portals: items }
        }
        None => snapshot
      }
    "billing-recorded" =>
      match event.billing {
        Some(value) => {
          let items = snapshot.billing.copy()
          items.push(value)
          { ..snapshot, billing: items }
        }
        None => snapshot
      }
    "repeat-order-recorded" =>
      match event.repeat_order {
        Some(value) => {
          let items = snapshot.repeat_orders.copy()
          items.push(value)
          { ..snapshot, repeat_orders: items }
        }
        None => snapshot
      }
    _ => snapshot
  }
  { ..next, revision: next.revision + 1 }
}

///|
pub fn replay_commercial(
  initial : CommercialSnapshot,
  events : Array[CommercialEvent],
) -> CommercialSnapshot {
  let mut snapshot = initial
  for event in events {
    snapshot = apply_commercial_event(snapshot, event)
  }
  snapshot
}

///|
fn quote_for(
  snapshot : CommercialSnapshot,
  reference : @project.VersionRef,
) -> ScopedQuote? {
  for quote in snapshot.quotes {
    if quote.quote == reference {
      return Some(quote)
    }
  }
  None
}

///|
fn lead_for(
  snapshot : CommercialSnapshot,
  reference : @project.VersionRef,
) -> QualifiedLead? {
  for lead in snapshot.leads {
    if lead.lead == reference {
      return Some(lead)
    }
  }
  None
}

///|
fn resource_for(
  snapshot : CommercialSnapshot,
  reference : @project.VersionRef,
) -> CapacityResource? {
  for resource in snapshot.resources {
    if resource.resource == reference {
      return Some(resource)
    }
  }
  None
}

///|
fn command_valid(command : CommercialCommand) -> Bool {
  match command.action {
    "record_lead" =>
      match command.lead {
        Some(lead) =>
          lead.customer != "" &&
          lead.payable_problem != "" &&
          lead.channels.length() > 0 &&
          lead.measurable_acceptance.length() > 0 &&
          lead.repeat_hypothesis != "" &&
          lead.baseline_cost_cny >= 0.0 &&
          lead.baseline_time_hours > 0.0
        None => false
      }
    "record_lead_decision" =>
      match command.lead_decision {
        Some(decision) =>
          lead_for(command.snapshot, decision.lead) is Some(_) &&
          (decision.decision == "qualify" || decision.decision == "disqualify") &&
          decision.actor != "" &&
          decision.actor_role != ""
        None => false
      }
    "record_quote" =>
      match command.quote {
        Some(quote) =>
          match lead_for(command.snapshot, quote.source_lead) {
            Some(lead) =>
              lead_is_qualified(lead, command.snapshot.lead_decisions) &&
              quote_terms_valid(quote)
            None => false
          }
        None => false
      }
    "record_quote_decision" =>
      match command.quote_decision {
        Some(decision) =>
          match quote_for(command.snapshot, decision.quote) {
            Some(quote) =>
              decision.actor != "" &&
              decision.actor_role != "" &&
              (if decision.authority == "client" {
                quote_is_internally_approved(
                  quote,
                  command.snapshot.quote_decisions,
                ) &&
                (decision.decision == "accept" || decision.decision == "reject")
              } else {
                (
                  decision.authority == "commercial" ||
                  decision.authority == "production"
                ) &&
                (
                  decision.decision == "approve" ||
                  decision.decision == "reject"
                )
              })
            None => false
          }
        None => false
      }
    "record_capacity_resource" =>
      match command.resource {
        Some(resource) =>
          resource.name != "" &&
          resource.role != "" &&
          resource.skills.length() > 0 &&
          resource.weekly_hours > 0.0 &&
          resource.weekly_hours <= 100.0 &&
          resource.available_from <= resource.available_to
        None => false
      }
    "record_capacity_reservation" =>
      match command.reservation {
        Some(reservation) =>
          quote_for(command.snapshot, reservation.quote) is Some(_) &&
          resource_for(command.snapshot, reservation.resource) is Some(_) &&
          reservation.hours > 0.0 &&
          reservation.skills.length() > 0 &&
          reservation.start_date <= reservation.end_date
        None => false
      }
    "record_capacity_board" =>
      match command.capacity_board {
        Some(board) =>
          quote_for(command.snapshot, board.quote) is Some(_) &&
          board.digest != ""
        None => false
      }
    "convert_quote" =>
      match command.conversion {
        Some(conversion) =>
          match quote_for(command.snapshot, conversion.quote) {
            Some(quote) =>
              quote_is_client_accepted(quote, command.snapshot.quote_decisions) &&
              command.snapshot.capacity_boards.any(board => {
                board.quote == quote.quote &&
                board.digest == conversion.capacity_digest &&
                board.ready
              }) &&
              !conversion.payment_effect_performed &&
              !conversion.publication_authority
            None => false
          }
        None => false
      }
    "record_client_portal" =>
      match command.portal {
        Some(portal) =>
          portal.project_id != "" &&
          portal.master_sha256 != "" &&
          portal.build_digest != "" &&
          portal.status == "active" &&
          portal.scopes.length() > 0 &&
          portal.created_by != ""
        None => false
      }
    "record_billing" =>
      match command.billing {
        Some(entry) =>
          entry.project_id != "" &&
          entry.amount >= 0.0 &&
          !entry.payment_effect_performed &&
          (
            entry.kind == "deposit" ||
            entry.kind == "animatic" ||
            entry.kind == "accepted-master" ||
            entry.kind == "provider-overage" ||
            entry.kind == "extra-revision"
          )
        None => false
      }
    "record_repeat_order" =>
      match command.repeat_order {
        Some(proposal) => repeat_order_safe(proposal)
        None => false
      }
    _ => false
  }
}

///|
fn event_kind(action : String) -> String? {
  match action {
    "record_lead" => Some("lead-recorded")
    "record_lead_decision" => Some("lead-decision-recorded")
    "record_quote" => Some("quote-recorded")
    "record_quote_decision" => Some("quote-decision-recorded")
    "record_capacity_resource" => Some("capacity-resource-recorded")
    "record_capacity_reservation" => Some("capacity-reservation-recorded")
    "record_capacity_board" => Some("capacity-board-recorded")
    "convert_quote" => Some("quote-converted")
    "record_client_portal" => Some("client-portal-recorded")
    "record_billing" => Some("billing-recorded")
    "record_repeat_order" => Some("repeat-order-recorded")
    _ => None
  }
}

///|
pub fn reduce_commercial_command(
  command : CommercialCommand,
) -> CommercialResult {
  let fail = fn(code : String) -> CommercialResult {
    {
      contract: "mooncast.commercial-result.v1",
      command_id: command.command_id,
      ok: false,
      error_code: Some(code),
      snapshot: command.snapshot,
      events: [],
      external_effect_performed: false,
      payment_effect_performed: false,
      publication_authority: false,
    }
  }
  if command.contract != "mooncast.commercial-command.v1" {
    return fail("contract_unsupported")
  }
  if command.expected_revision != command.snapshot.revision {
    return fail("commercial_revision_conflict")
  }
  if command.command_id == "" ||
    command.recorded_at == "" ||
    command.evidence_digest == "" {
    return fail("command_evidence_required")
  }
  let kind = event_kind(command.action)
  if kind is None || !command_valid(command) {
    return fail("commercial_command_invalid")
  }
  let event = event_from(command, kind.unwrap())
  let snapshot = apply_commercial_event(command.snapshot, event)
  {
    contract: "mooncast.commercial-result.v1",
    command_id: command.command_id,
    ok: true,
    error_code: None,
    snapshot,
    events: [event],
    external_effect_performed: false,
    payment_effect_performed: false,
    publication_authority: false,
  }
}
