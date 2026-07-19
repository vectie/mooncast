///|
pub async fn CommercialApplicationService::lead(
  self : CommercialApplicationService,
  lead_id : String,
) -> @commerce_domain.QualifiedLead? {
  let snapshot = self.load()
  let mut current : @commerce_domain.QualifiedLead? = None
  for lead in snapshot.leads {
    if lead.lead.id == lead_id {
      match current {
        None => current = Some(lead)
        Some(previous) =>
          if lead.lead.version > previous.lead.version {
            current = Some(lead)
          }
      }
    }
  }
  current
}

///|
pub async fn CommercialApplicationService::quote(
  self : CommercialApplicationService,
  quote_id : String,
) -> @commerce_domain.ScopedQuote? {
  let snapshot = self.load()
  let mut current : @commerce_domain.ScopedQuote? = None
  for quote in snapshot.quotes {
    if quote.quote.id == quote_id {
      match current {
        None => current = Some(quote)
        Some(previous) =>
          if quote.quote.version > previous.quote.version {
            current = Some(quote)
          }
      }
    }
  }
  current
}

///|
pub async fn CommercialApplicationService::capacity_board(
  self : CommercialApplicationService,
  quote_id? : String,
) -> @commerce_domain.CapacityBoard? {
  let snapshot = self.load()
  let mut current : @commerce_domain.CapacityBoard? = None
  for board in snapshot.capacity_boards {
    if quote_id is None || quote_id == Some(board.quote.id) {
      current = Some(board)
    }
  }
  current
}

///|
pub async fn CommercialApplicationService::repeat_orders(
  self : CommercialApplicationService,
  source_project_id : String,
) -> Array[@commerce_domain.RepeatOrderProposal] {
  let snapshot = self.load()
  snapshot.repeat_orders.filter(order => {
    order.source_project_id == source_project_id
  })
}

///|
pub async fn CommercialApplicationService::portals_for_project(
  self : CommercialApplicationService,
  project_id : String,
) -> Array[@commerce_domain.ClientPortal] {
  let snapshot = self.load()
  snapshot.portals.filter(portal => portal.project_id == project_id)
}

///|
pub async fn CommercialApplicationService::reschedule_reservation(
  self : CommercialApplicationService,
  expected : @commerce_domain.CapacityReservation,
  updated : @commerce_domain.CapacityReservation,
) -> @commerce_domain.CapacityReservation {
  let snapshot = self.load()
  let exact = snapshot.reservations.filter(item => {
    item.reservation == expected.reservation
  })
  if exact.length() != 1 ||
    updated.reservation.id != expected.reservation.id ||
    updated.reservation.version != expected.reservation.version + 1 ||
    updated.quote != expected.quote ||
    updated.resource != expected.resource ||
    updated.start_date > updated.end_date ||
    updated.hours <= 0.0 {
    raise CommercialCommandRejected("capacity_reservation_conflict")
  }
  let reservations = snapshot.reservations.filter(item => {
    item.reservation != expected.reservation
  })
  reservations.push(updated)
  let revision = snapshot.revision + 1
  self.save({ ..snapshot, revision, reservations })
  self.audit_action(
    "capacity.rescheduled",
    @runtime.new_id(prefix="capacity-reschedule"),
    "sha256:" +
    @crypto.bytes_to_hex_string(
      @crypto.sha256(@utf8.encode(updated.to_json().stringify())),
    ),
    @runtime.wall_clock_ms().to_string(),
    revision,
  )
  updated
}

///|
pub async fn CommercialApplicationService::control_portal(
  self : CommercialApplicationService,
  portal_id : String,
  expected_revision : Int,
  action : String,
  actor : String,
  observed_at : String,
  record_digest : String,
) -> @commerce_domain.ClientPortal {
  let snapshot = self.load()
  let matches = snapshot.portals.filter(portal => portal.portal_id == portal_id)
  if matches.length() != 1 ||
    matches[0].revision != expected_revision ||
    actor == "" ||
    (action != "revoke" && action != "expire") {
    raise CommercialCommandRejected("client_portal_conflict")
  }
  let portal = {
    ..matches[0],
    status: if action == "revoke" {
      "revoked"
    } else {
      "expired"
    },
    revision: matches[0].revision + 1,
    updated_at: observed_at,
    record_digest,
  }
  let portals = snapshot.portals.filter(item => item.portal_id != portal_id)
  portals.push(portal)
  let revision = snapshot.revision + 1
  self.save({ ..snapshot, revision, portals })
  self.audit_action(
    "portal." + action,
    @runtime.new_id(prefix="portal-control"),
    record_digest,
    observed_at,
    revision,
  )
  portal
}
