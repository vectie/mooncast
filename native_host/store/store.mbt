///|
pub(all) struct StoredBlob {
  key : String
  bytes : Bytes
  sha256 : String
} derive(Debug, Eq)

///|
pub struct AtomicStore {
  root : String
  max_read_bytes : Int
}

///|
pub suberror StoreError {
  InvalidKey(String)
  ObjectTooLarge(key~ : String, size~ : Int64, limit~ : Int)
  InvalidJson(String)
} derive(Debug)

///|
pub fn AtomicStore::new(
  root : String,
  max_read_bytes? : Int = 268435456,
) -> AtomicStore {
  { root, max_read_bytes }
}

///|
fn valid_key(key : String) -> Bool {
  if key.is_empty() {
    return false
  }
  for char in key {
    match char {
      'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' | '.' => ()
      _ => return false
    }
  }
  key != "." && key != ".."
}

///|
fn AtomicStore::path(
  self : AtomicStore,
  key : String,
) -> String raise StoreError {
  guard valid_key(key) else { raise InvalidKey(key) }
  self.root + "/" + key
}

///|
/// Returns the host path for a validated store-owned key. This is the narrow
/// bridge used by typed process ports such as ffmpeg: callers still cannot
/// provide an arbitrary path or escape the store root.
pub fn AtomicStore::owned_path(
  self : AtomicStore,
  key : String,
) -> String raise StoreError {
  self.path(key)
}

///|
/// Prepare a validated store-owned destination for an argv-only native tool.
/// The caller receives no arbitrary filesystem authority: the key is checked
/// by the same flat-key policy as every other store operation and the owning
/// directory is created by the store itself.
pub async fn AtomicStore::prepare_owned_path(
  self : AtomicStore,
  key : String,
) -> String {
  let path = self.path(key)
  self.ensure_root()
  path
}

///|
fn digest(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
async fn AtomicStore::ensure_root(self : AtomicStore) -> Unit {
  if @fs.exists(self.root) {
    guard @fs.kind(self.root) is Directory else {
      fail("atomic store root is not a directory")
    }
    return
  }
  @fs.mkdir(self.root, permission=0o700, recursive=true) catch {
    error => {
      // Another writer may create the same durable root after the existence
      // check. Treat that race as success only when the final object is the
      // directory this store owns; every other filesystem error remains fatal.
      guard @fs.exists(self.root) && @fs.kind(self.root) is Directory else {
        raise error
      }
    }
  }
}

///|
#warnings("-alert_internal")
pub async fn AtomicStore::put_blob(
  self : AtomicStore,
  key : String,
  bytes : Bytes,
) -> StoredBlob {
  let destination = self.path(key)
  self.ensure_root()
  let nonce = @crypto.bytes_to_hex_string(@tls.rand_bytes(8))
  let temporary = destination + ".tmp-" + @async.now().to_string() + "-" + nonce
  let file = @fs.create(temporary, permission=0o600, sync=Full)
  try {
    file.write(bytes)
    file.sync()
    file.close()
    @fsx.atomic_rename(temporary, destination)
  } catch {
    error => {
      file.close()
      if @fs.exists(temporary) {
        @fs.remove(temporary) catch {
          _ => ()
        }
      }
      raise error
    }
  }
  { key, bytes, sha256: digest(bytes) }
}

///|
pub async fn AtomicStore::get_blob(
  self : AtomicStore,
  key : String,
) -> StoredBlob? {
  let path = self.path(key)
  guard @fs.exists(path) else { return None }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size <= self.max_read_bytes.to_int64() else {
    raise ObjectTooLarge(key~, size~, limit=self.max_read_bytes)
  }
  let bytes = file.read_exactly_at(size.to_int(), position=0)
  { key, bytes, sha256: digest(bytes) } |> Some
}

///|
pub async fn AtomicStore::put_json(
  self : AtomicStore,
  key : String,
  value : Json,
) -> StoredBlob {
  let text = value.stringify()
  self.put_blob(key, @utf8.encode(text))
}

///|
pub async fn AtomicStore::get_json(self : AtomicStore, key : String) -> Json? {
  match self.get_blob(key) {
    None => None
    Some(record) => {
      let text = @utf8.decode(record.bytes)
      let value = @json.parse(text) catch { _ => raise InvalidJson(key) }
      Some(value)
    }
  }
}

///|
pub async fn AtomicStore::remove(self : AtomicStore, key : String) -> Bool {
  let path = self.path(key)
  guard @fs.exists(path) else { return false }
  @fs.remove(path)
  true
}

///|
pub async fn AtomicStore::list_keys(
  self : AtomicStore,
  prefix? : String = "",
  suffix? : String = "",
) -> Array[String] {
  guard @fs.exists(self.root) else { return [] }
  let names = @fs.readdir(
    self.root,
    include_hidden=false,
    include_special=false,
    sort=true,
  )
  names.filter(name => {
    valid_key(name) && name.has_prefix(prefix) && name.has_suffix(suffix)
  })
}
