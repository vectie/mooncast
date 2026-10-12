///|
pub(all) struct Replacement {
  media_ref_id : String
  new_uri : String
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A source-bound local plan. A subset of media IDs may be changed.
pub(all) struct RelinkMap {
  contract : String
  source_binding : String
  replacements : Array[Replacement]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct InventoryRow {
  media_ref_id : String
  uri : String
  sha256 : String
  size_bytes : Int
  clip_ids : Array[String]
} derive(Eq, Debug, ToJson)

///|
pub(all) struct Change {
  media_ref_id : String
  before_uri : String
  after_uri : String
} derive(Eq, Debug, ToJson)

///|
pub(all) struct RelinkResult {
  project : @domain.EditorProject
  changes : Array[Change]
} derive(Eq, Debug, ToJson)

///|
/// Matches the existing native media-reference schema's portable URI profile.
pub fn safe_uri(uri : String) -> Bool {
  !uri.is_empty() &&
  uri.length() <= 1024 &&
  !uri.has_prefix("/") &&
  !uri.contains("..") &&
  uri.split("/").all(part => !part.is_empty() && part != ".") &&
  uri
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '.' ||
    c == '_' ||
    c == '-' ||
    c == '/'
  })
}

///|
fn validate(project : @domain.EditorProject) -> Unit raise {
  guard project.contract == "mooncast.editor-project.v1" &&
    project.timeline.contract == "mooncast.editor-timeline.v1" &&
    project.revision >= 0 &&
    !project.project_id.trim().is_empty() else {
    fail("unsupported project contract, identity or revision")
  }
  guard project.media_refs.length() > 0 && project.media_refs.length() <= 1000 else {
    fail("expected 1–1000 media references")
  }
  let ids : Map[String, Bool] = {}
  for media in project.media_refs {
    let id = media.media_ref_id
    guard !id.is_empty() && !ids.contains(id) else {
      fail("empty or duplicate media ID: " + id)
    }
    ids[id] = true
    guard media.contract == "mooncast.editor-media-ref.v1" &&
      media.locator.kind == "pack-relative" &&
      safe_uri(media.locator.uri) else {
      fail("unsupported or unsafe media locator: " + id)
    }
    guard media.metadata.size_bytes >= 0 &&
      media.metadata.sha256.length() == 64 &&
      media.metadata.sha256
      .iter()
      .all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) else {
      fail("media needs a lowercase SHA-256 and known size: " + id)
    }
  }
  for track in project.timeline.tracks {
    for clip in track.clips {
      guard ids.contains(clip.media_ref_id) else {
        fail("clip references unknown media: " + clip.clip_id)
      }
    }
  }
}

///|
/// This binding identifies typed project content, not rights or authorship.
pub fn binding(project : @domain.EditorProject) -> String raise {
  validate(project)
  "sha256:" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(@domain.snapshot_to_json(project))),
  )
}

///|
/// No filesystem reads: only list declared media and where each is used.
pub fn inventory(project : @domain.EditorProject) -> Array[InventoryRow] raise {
  validate(project)
  project.media_refs.map(media => {
    let clip_ids = []
    for track in project.timeline.tracks {
      for clip in track.clips {
        if clip.media_ref_id == media.media_ref_id {
          clip_ids.push(clip.clip_id)
        }
      }
    }
    {
      media_ref_id: media.media_ref_id,
      uri: media.locator.uri,
      sha256: media.metadata.sha256,
      size_bytes: media.metadata.size_bytes,
      clip_ids,
    }
  })
}

///|
pub fn seed(project : @domain.EditorProject) -> RelinkMap raise {
  {
    contract: "mooncast.media-relink-map.v1",
    source_binding: binding(project),
    replacements: project.media_refs.map(media => {
      media_ref_id: media.media_ref_id,
      new_uri: media.locator.uri,
    }),
  }
}

///|
pub fn read_map(text : String) -> RelinkMap raise {
  guard @utf8.encode(text).length() <= 2097152 else {
    fail("relink map exceeds 2 MiB")
  }
  @json.from_json(@json.parse(text))
}

///|
/// Prepare a detached native snapshot. The caller must verify every resulting
/// media file before persisting it. Does not mutate the original project.
pub fn prepare(
  project : @domain.EditorProject,
  map : RelinkMap,
) -> RelinkResult raise {
  guard map.contract == "mooncast.media-relink-map.v1" &&
    map.source_binding == binding(project) else {
    fail(
      "wrong map contract or stale source binding; seed from current project",
    )
  }
  guard map.replacements.length() > 0 &&
    map.replacements.length() <= project.media_refs.length() else {
    fail("expected a nonempty mapping, at most one row per media ID")
  }
  let uris : Map[String, String] = {}
  for row in map.replacements {
    guard !uris.contains(row.media_ref_id) &&
      project.media_refs.any(media => media.media_ref_id == row.media_ref_id) else {
      fail("duplicate or unknown mapped media ID: " + row.media_ref_id)
    }
    guard safe_uri(row.new_uri) else {
      fail(
        "new URI must use the portable pack-relative path profile: " +
        row.media_ref_id,
      )
    }
    uris[row.media_ref_id] = row.new_uri
  }
  let changes = []
  let media_refs = project.media_refs.map(media => {
    let uri = uris.get(media.media_ref_id).unwrap_or(media.locator.uri)
    if uri != media.locator.uri {
      changes.push({
        media_ref_id: media.media_ref_id,
        before_uri: media.locator.uri,
        after_uri: uri,
      })
    }
    { ..media, locator: { kind: "pack-relative", uri, }, }
  })
  guard changes.is_empty() || project.revision < 2147483647 else {
    fail("project revision exhausted; cannot create a relinked revision")
  }
  {
    project: {
      ..project,
      revision: if changes.is_empty() {
        project.revision
      } else {
        project.revision + 1
      },
      media_refs,
    },
    changes,
  }
}
