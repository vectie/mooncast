///|
pub(all) struct CapacityResource {
  contract : String
  resource : @project.VersionRef
  name : String
  role : String
  skills : Array[String]
  weekly_hours : Double
  available_from : String
  available_to : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapacityReservation {
  contract : String
  reservation : @project.VersionRef
  quote : @project.VersionRef
  resource : @project.VersionRef
  role : String
  skills : Array[String]
  start_date : String
  end_date : String
  hours : Double
  depends_on : Array[String]
  status : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapacityConflict {
  kind : String
  resource_id : String
  reservation_id : String
  conflicting_reservation_id : String?
  detail : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapacityBoard {
  contract : String
  quote : @project.VersionRef
  reservation_ids : Array[String]
  conflicts : Array[CapacityConflict]
  ready : Bool
  calculated_at : String
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
fn overlaps(first : CapacityReservation, second : CapacityReservation) -> Bool {
  first.start_date <= second.end_date && second.start_date <= first.end_date
}

///|
pub fn calculate_capacity(
  quote : ScopedQuote,
  resources : Array[CapacityResource],
  reservations : Array[CapacityReservation],
  calculated_at : String,
  digest : String,
) -> CapacityBoard {
  let exact = reservations.filter(item => {
    item.quote == quote.quote && item.status == "reserved"
  })
  let conflicts : Array[CapacityConflict] = []
  for reservation in exact {
    let found = resources.filter(resource => {
      resource.resource == reservation.resource
    })
    if found.length() != 1 {
      conflicts.push({
        kind: "missing-resource",
        resource_id: reservation.resource.id,
        reservation_id: reservation.reservation.id,
        conflicting_reservation_id: None,
        detail: "reservation resource is unavailable",
      })
    } else {
      let resource = found[0]
      if reservation.hours <= 0.0 ||
        reservation.start_date < resource.available_from ||
        reservation.end_date > resource.available_to ||
        reservation.start_date < quote.start_date ||
        reservation.end_date > quote.delivery_date ||
        !reservation.skills.all(skill => {
          resource.skills.any(value => value == skill)
        }) {
        conflicts.push({
          kind: "reservation-outside-capacity",
          resource_id: resource.resource.id,
          reservation_id: reservation.reservation.id,
          conflicting_reservation_id: None,
          detail: "date, hours, or skills do not fit",
        })
      }
    }
    for other in exact {
      if other.reservation.id != reservation.reservation.id &&
        other.resource == reservation.resource &&
        overlaps(reservation, other) &&
        reservation.reservation.id < other.reservation.id {
        let resource_hours = if found.length() == 1 {
          found[0].weekly_hours
        } else {
          0.0
        }
        if reservation.hours + other.hours > resource_hours {
          conflicts.push({
            kind: "over-capacity",
            resource_id: reservation.resource.id,
            reservation_id: reservation.reservation.id,
            conflicting_reservation_id: Some(other.reservation.id),
            detail: "overlapping reservations exceed weekly capacity",
          })
        }
      }
    }
  }
  {
    contract: "mooncast.capacity-board.v1",
    quote: quote.quote,
    reservation_ids: exact.map(item => item.reservation.id),
    conflicts,
    ready: exact.length() > 0 && conflicts.length() == 0,
    calculated_at,
    digest,
  }
}
