///|
pub(all) struct CollectedFile {
  source_uri : String
  uri : String
  sha256 : String
  size_bytes : Int
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct Member {
  media_ref_id : String
  source_uri : String
  uri : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct CollectionPlan {
  source_binding : String
  project : @domain.EditorProject
  files : Array[CollectedFile]
  members : Array[Member]
  total_size_bytes : Int64
} derive(ToJson)

///|
pub(all) struct CollectionManifest {
  contract : String
  source_binding : String
  project_binding : String
  project_sha256 : String
  files : Array[CollectedFile]
  members : Array[Member]
  total_size_bytes : Int64
} derive(Eq, Debug, ToJson, FromJson)

///|
pub fn digest(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
/// Keep the source suffix because some existing consumers select parsers by it.
fn collected_uri(row : @relink.InventoryRow) -> String {
  let name = row.uri.split("/").last().unwrap().to_string()
  let parts = name.split(".").to_array()
  let suffix = if parts.length() > 1 && !parts.last().unwrap().is_empty() {
    "." + parts.last().unwrap().to_string()
  } else {
    ""
  }
  "media/" + row.sha256 + suffix
}

///|
/// All native media references are retained, including unused library assets.
/// Files with the same content and suffix are copied once; media IDs never merge.
pub fn prepare(project : @domain.EditorProject) -> CollectionPlan raise {
  let rows = @relink.inventory(project)
  let files : Array[CollectedFile] = []
  let members : Array[Member] = []
  let sizes : Map[String, Int] = {}
  let outputs : Map[String, Bool] = {}
  let mut total = 0L
  let mut source_total = 0L
  for row in rows {
    guard row.size_bytes <= 268435456 else {
      fail("media exceeds 256 MiB: " + row.media_ref_id)
    }
    source_total += row.size_bytes.to_int64()
    guard source_total <= 4294967296L else {
      fail("source verification exceeds 4 GiB")
    }
    match sizes.get(row.sha256) {
      Some(size) if size != row.size_bytes =>
        fail("one SHA-256 declares conflicting byte sizes")
      _ => sizes[row.sha256] = row.size_bytes
    }
    let uri = collected_uri(row)
    members.push({ media_ref_id: row.media_ref_id, source_uri: row.uri, uri, })
    if !outputs.contains(uri) {
      outputs[uri] = true
      total += row.size_bytes.to_int64()
      files.push({
        source_uri: row.uri,
        uri,
        sha256: row.sha256,
        size_bytes: row.size_bytes,
      })
    }
  }
  guard total <= 4294967296L else { fail("collection exceeds 4 GiB") }
  let source_binding = @relink.binding(project)
  let result = @relink.prepare(project, {
    contract: "mooncast.media-relink-map.v1",
    source_binding,
    replacements: members.map(m => {
      media_ref_id: m.media_ref_id,
      new_uri: m.uri,
    }),
  })
  {
    source_binding,
    project: result.project,
    files,
    members,
    total_size_bytes: total,
  }
}

///|
pub fn CollectionPlan::manifest(
  self : CollectionPlan,
  project_bytes : Bytes,
) -> CollectionManifest raise {
  guard @relink.binding(@domain.snapshot_from_json(@utf8.decode(project_bytes))) ==
    @relink.binding(self.project) else {
    fail("project bytes do not match plan")
  }
  {
    contract: "mooncast.project-collection.v1",
    source_binding: self.source_binding,
    project_binding: @relink.binding(self.project),
    project_sha256: digest(project_bytes),
    files: self.files,
    members: self.members,
    total_size_bytes: self.total_size_bytes,
  }
}

///|
pub fn read_manifest(text : String) -> CollectionManifest raise {
  guard @utf8.encode(text).length() <= 2097152 else {
    fail("manifest exceeds 2 MiB")
  }
  @json.from_json(@json.parse(text))
}

///|
/// Validate a relocated bundle's snapshot and complete media inventory before I/O.
/// This checks local consistency, not an authenticated sender or rights evidence.
pub fn verify_manifest(
  manifest : CollectionManifest,
  project_bytes : Bytes,
) -> @domain.EditorProject raise {
  guard manifest.contract == "mooncast.project-collection.v1" &&
    manifest.project_sha256 == digest(project_bytes) else {
    fail("collection contract or project byte digest mismatch")
  }
  let project = @domain.snapshot_from_json(@utf8.decode(project_bytes))
  let expected = prepare(project)
  guard manifest.project_binding == @relink.binding(project) &&
    expected.project == project &&
    manifest.total_size_bytes == expected.total_size_bytes &&
    manifest.files.length() == expected.files.length() &&
    manifest.members.length() == expected.members.length() else {
    fail("collection project binding or inventory mismatch")
  }
  for i, file in manifest.files {
    let item = expected.files[i]
    guard file.uri == item.uri &&
      file.sha256 == item.sha256 &&
      file.size_bytes == item.size_bytes &&
      @relink.safe_uri(file.source_uri) else {
      fail("collection file inventory mismatch")
    }
  }
  for i, entry in manifest.members {
    let item = expected.members[i]
    guard entry.media_ref_id == item.media_ref_id &&
      entry.uri == item.uri &&
      @relink.safe_uri(entry.source_uri) else {
      fail("collection member inventory mismatch")
    }
  }
  project
}
