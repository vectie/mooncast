///|
pub(all) struct ImmutableRecordEnvelope {
  contract : String
  record_type : String
  record_id : String
  idempotency_key : String
  payload_digest : String
  previous_anchor_digest : String?
  envelope_digest : String
  payload : Json
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ImmutablePutResult {
  envelope : ImmutableRecordEnvelope
  created : Bool
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ImmutableChainVerification {
  record_type : String
  valid : Bool
  record_count : Int
  anchor_digest : String?
  error_code : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub suberror ImmutableRecordError {
  InvalidRecordIdentity(String)
  ImmutableRecordConflict(String)
  ImmutableRecordCorrupt(String)
} derive(Debug)

///|
pub struct ImmutableRecordStore {
  store : @store.AtomicStore
}

///|
pub fn ImmutableRecordStore::new(root : String) -> ImmutableRecordStore {
  { store: @store.AtomicStore::new(root, max_read_bytes=33554432) }
}

///|
fn safe_record_identity(value : String) -> Bool {
  if value.length() < 1 || value.length() > 128 {
    return false
  }
  for char in value {
    match char {
      'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' | '.' => ()
      _ => return false
    }
  }
  true
}

///|
pub fn valid_record_id(value : String) -> Bool {
  safe_record_identity(value)
}

///|
fn immutable_digest(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
pub fn canonical_record_json(value : Json) -> String {
  value.stringify()
}

///|
pub fn canonical_record_digest(value : Json) -> String {
  immutable_digest(canonical_record_json(value))
}

///|
fn immutable_key(record_type : String, record_id : String) -> String {
  "immutable-" + record_type + "-" + record_id + ".json"
}

///|
fn idempotency_key(value : String) -> String {
  "idempotency-" + value + ".json"
}

///|
fn anchor_key(record_type : String) -> String {
  "anchor-" + record_type + ".json"
}

///|
pub async fn ImmutableRecordStore::get(
  self : ImmutableRecordStore,
  record_type : String,
  record_id : String,
) -> ImmutableRecordEnvelope? {
  if !safe_record_identity(record_type) || !safe_record_identity(record_id) {
    raise InvalidRecordIdentity(record_type + ":" + record_id)
  }
  match self.store.get_json(immutable_key(record_type, record_id)) {
    None => None
    Some(value) => {
      let envelope : ImmutableRecordEnvelope = @json.from_json(value) catch {
        _ => raise ImmutableRecordCorrupt(record_type + ":" + record_id)
      }
      if envelope.payload_digest !=
        immutable_digest(envelope.payload.stringify()) {
        raise ImmutableRecordCorrupt(record_type + ":" + record_id)
      }
      Some(envelope)
    }
  }
}

///|
pub async fn ImmutableRecordStore::put(
  self : ImmutableRecordStore,
  record_type : String,
  record_id : String,
  idempotency : String,
  payload : Json,
) -> ImmutablePutResult {
  if !safe_record_identity(record_type) ||
    !safe_record_identity(record_id) ||
    !safe_record_identity(idempotency) {
    raise InvalidRecordIdentity(record_type + ":" + record_id)
  }
  let payload_digest = immutable_digest(payload.stringify())
  match self.store.get_json(idempotency_key(idempotency)) {
    Some(value) => {
      let existing : ImmutableRecordEnvelope = @json.from_json(value) catch {
        _ => raise ImmutableRecordCorrupt(idempotency)
      }
      if existing.record_type != record_type ||
        existing.record_id != record_id ||
        existing.payload_digest != payload_digest {
        raise ImmutableRecordConflict(idempotency)
      }
      return { envelope: existing, created: false }
    }
    None => ()
  }
  if self.get(record_type, record_id) is Some(_) {
    raise ImmutableRecordConflict(record_type + ":" + record_id)
  }
  let previous_anchor = match self.store.get_json(anchor_key(record_type)) {
    None => None
    Some(value) =>
      match value {
        String(digest) => Some(digest)
        _ => raise ImmutableRecordCorrupt(record_type + ":anchor")
      }
  }
  let core = record_type +
    ":" +
    record_id +
    ":" +
    idempotency +
    ":" +
    payload_digest +
    ":" +
    previous_anchor.unwrap_or("")
  let envelope : ImmutableRecordEnvelope = {
    contract: "mooncast.immutable-record-envelope.v1",
    record_type,
    record_id,
    idempotency_key: idempotency,
    payload_digest,
    previous_anchor_digest: previous_anchor,
    envelope_digest: immutable_digest(core),
    payload,
  }
  ignore(
    self.store.put_json(
      immutable_key(record_type, record_id),
      envelope.to_json(),
    ),
  )
  ignore(self.store.put_json(idempotency_key(idempotency), envelope.to_json()))
  ignore(
    self.store.put_json(
      anchor_key(record_type),
      envelope.envelope_digest.to_json(),
    ),
  )
  { envelope, created: true }
}

///|
pub async fn ImmutableRecordStore::list(
  self : ImmutableRecordStore,
  record_type : String,
) -> Array[ImmutableRecordEnvelope] {
  if !safe_record_identity(record_type) {
    raise InvalidRecordIdentity(record_type)
  }
  let records : Array[ImmutableRecordEnvelope] = []
  for
    key in self.store.list_keys(
      prefix="immutable-" + record_type + "-",
      suffix=".json",
    ) {
    match self.store.get_json(key) {
      None => ()
      Some(value) => {
        let envelope : ImmutableRecordEnvelope = @json.from_json(value) catch {
          _ => raise ImmutableRecordCorrupt(key)
        }
        records.push(envelope)
      }
    }
  }
  records
}

///|
pub async fn ImmutableRecordStore::verify(
  self : ImmutableRecordStore,
  record_type : String,
) -> ImmutableChainVerification {
  let records = self.list(record_type)
  let anchor = match self.store.get_json(anchor_key(record_type)) {
    Some(String(value)) => Some(value)
    None => None
    _ =>
      return {
        record_type,
        valid: false,
        record_count: records.length(),
        anchor_digest: None,
        error_code: Some("anchor_corrupt"),
      }
  }
  let mut expected : String? = None
  let visited : Array[String] = []
  for _ in 0..<records.length() {
    let mut next : ImmutableRecordEnvelope? = None
    for record in records {
      if record.previous_anchor_digest == expected &&
        !visited.any(digest => digest == record.envelope_digest) {
        if next is Some(_) {
          return {
            record_type,
            valid: false,
            record_count: records.length(),
            anchor_digest: anchor,
            error_code: Some("chain_fork"),
          }
        }
        next = Some(record)
      }
    }
    match next {
      None =>
        return {
          record_type,
          valid: false,
          record_count: records.length(),
          anchor_digest: anchor,
          error_code: Some("chain_gap"),
        }
      Some(record) => {
        if record.payload_digest != immutable_digest(record.payload.stringify()) {
          return {
            record_type,
            valid: false,
            record_count: records.length(),
            anchor_digest: anchor,
            error_code: Some("payload_digest_mismatch"),
          }
        }
        visited.push(record.envelope_digest)
        expected = Some(record.envelope_digest)
      }
    }
  }
  {
    record_type,
    valid: expected == anchor,
    record_count: records.length(),
    anchor_digest: anchor,
    error_code: if expected == anchor {
      None
    } else {
      Some("anchor_mismatch")
    },
  }
}
