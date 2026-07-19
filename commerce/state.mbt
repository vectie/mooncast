///|
pub(all) struct CommercialSnapshot {
  contract : String
  revision : Int
  leads : Array[QualifiedLead]
  lead_decisions : Array[LeadQualificationDecision]
  quotes : Array[ScopedQuote]
  quote_decisions : Array[QuoteDecision]
  resources : Array[CapacityResource]
  reservations : Array[CapacityReservation]
  capacity_boards : Array[CapacityBoard]
  conversions : Array[QuoteConversion]
  portals : Array[ClientPortal]
  billing : Array[MilestoneBillingEntry]
  repeat_orders : Array[RepeatOrderProposal]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn empty_commercial_snapshot() -> CommercialSnapshot {
  {
    contract: "mooncast.commercial-snapshot.v1",
    revision: 0,
    leads: [],
    lead_decisions: [],
    quotes: [],
    quote_decisions: [],
    resources: [],
    reservations: [],
    capacity_boards: [],
    conversions: [],
    portals: [],
    billing: [],
    repeat_orders: [],
  }
}

///|
pub(all) struct CommercialEvent {
  contract : String
  event_id : String
  kind : String
  recorded_at : String
  evidence_digest : String
  lead : QualifiedLead?
  lead_decision : LeadQualificationDecision?
  quote : ScopedQuote?
  quote_decision : QuoteDecision?
  resource : CapacityResource?
  reservation : CapacityReservation?
  capacity_board : CapacityBoard?
  conversion : QuoteConversion?
  portal : ClientPortal?
  billing : MilestoneBillingEntry?
  repeat_order : RepeatOrderProposal?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CommercialCommand {
  contract : String
  command_id : String
  action : String
  recorded_at : String
  evidence_digest : String
  expected_revision : Int
  snapshot : CommercialSnapshot
  lead : QualifiedLead?
  lead_decision : LeadQualificationDecision?
  quote : ScopedQuote?
  quote_decision : QuoteDecision?
  resource : CapacityResource?
  reservation : CapacityReservation?
  capacity_board : CapacityBoard?
  conversion : QuoteConversion?
  portal : ClientPortal?
  billing : MilestoneBillingEntry?
  repeat_order : RepeatOrderProposal?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CommercialResult {
  contract : String
  command_id : String
  ok : Bool
  error_code : String?
  snapshot : CommercialSnapshot
  events : Array[CommercialEvent]
  external_effect_performed : Bool
  payment_effect_performed : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)
