///|
fn workspace_asset_entry_key(artifact_id : String, version : Int) -> String {
  "workspace-asset-entry-" +
  sha256_text(artifact_id + "\u{0000}" + version.to_string()) +
  ".json"
}

///|
fn workspace_artifact_kind_name(kind : @workspace.ArtifactKind) -> String {
  match kind {
    @workspace.TextArtifact => "TextArtifact"
    @workspace.ImageArtifact => "ImageArtifact"
    @workspace.AudioArtifact => "AudioArtifact"
    @workspace.VideoArtifact => "VideoArtifact"
    @workspace.MediaCollection => "MediaCollection"
    @workspace.ShotCollection => "ShotCollection"
    @workspace.TimelineArtifact => "TimelineArtifact"
    @workspace.ReviewDecisionArtifact => "ReviewDecisionArtifact"
    @workspace.DeliveryPackageArtifact => "DeliveryPackageArtifact"
    @workspace.DataArtifact => "DataArtifact"
    @workspace.AnyArtifact => "AnyArtifact"
  }
}

///|
async fn StudioService::workspace_asset_entry(
  self : StudioService,
  artifact_id : String,
  version : Int,
) -> @workspace.WorkspaceAssetEntry {
  let value : @workspace.WorkspaceAssetEntry? = load_value(
    self.store,
    workspace_asset_entry_key(artifact_id, version),
  )
  match value {
    Some(entry) => entry
    None => {
      let artifact : @workspace.WorkspaceArtifact? = load_value(
        self.store,
        workspace_artifact_key(artifact_id, version),
      )
      guard artifact is Some(artifact) else {
        raise NotFound(entity="workspace_asset", id=artifact_id)
      }
      let entry : @workspace.WorkspaceAssetEntry = {
        contract: "mooncast.workspace-asset-entry.v1",
        artifact,
        tags: [],
        deleted: false,
        indexed_at: artifact.created_at,
        updated_at: artifact.created_at,
      }
      save_value(
        self.store,
        workspace_asset_entry_key(artifact_id, version),
        entry,
      )
      entry
    }
  }
}

///|
fn workspace_asset_matches(
  entry : @workspace.WorkspaceAssetEntry,
  project_id : String,
  normalized : StringView,
  kind : String,
  tag : String,
  include_deleted : Bool,
) -> Bool {
  guard entry.artifact.project_id == project_id &&
    (include_deleted || !entry.deleted) &&
    (
      kind.is_blank() ||
      workspace_artifact_kind_name(entry.artifact.kind) == kind
    ) &&
    (tag.is_blank() || entry.tags.contains(tag)) else {
    return false
  }
  let searchable = (entry.artifact.artifact_id +
  " " +
  entry.artifact.node_id +
  " " +
  entry.artifact.provider +
  " " +
  entry.tags.join(" ")).to_lower()
  normalized.is_blank() || searchable.contains(normalized)
}

///|
pub async fn StudioService::list_workspace_asset_library(
  self : StudioService,
  project_id : String,
  query : String,
  kind : String,
  tag : String,
  offset : Int,
  limit : Int,
  include_deleted : Bool,
) -> WorkspaceAssetLibraryProjection {
  guard valid_id(project_id) && offset >= 0 && limit >= 1 && limit <= 200 else {
    raise Invalid(
      code="workspace_asset_query_invalid",
      message="asset query requires a valid project and a limit from 1 to 200",
    )
  }
  let normalized = query.trim().to_lower()
  let matching : Array[@workspace.WorkspaceAssetEntry] = []
  let indexed : Array[String] = []
  for
    key in self.store.list_keys(prefix="workspace-asset-entry-", suffix=".json") {
    let value : @workspace.WorkspaceAssetEntry? = load_value(self.store, key)
    if value is Some(entry) {
      indexed.push(
        entry.artifact.artifact_id + ":" + entry.artifact.version.to_string(),
      )
      if workspace_asset_matches(
          entry, project_id, normalized, kind, tag, include_deleted,
        ) {
        matching.push(entry)
      }
    }
  }
  // Existing installations may predate the asset index. Migrate those
  // immutable artifact versions lazily without changing their evidence.
  for artifact in self.list_workspace_artifacts(project_id~).artifacts {
    let identity = artifact.artifact_id + ":" + artifact.version.to_string()
    if !indexed.contains(identity) {
      let entry : @workspace.WorkspaceAssetEntry = {
        contract: "mooncast.workspace-asset-entry.v1",
        artifact,
        tags: [],
        deleted: false,
        indexed_at: artifact.created_at,
        updated_at: artifact.created_at,
      }
      save_value(
        self.store,
        workspace_asset_entry_key(artifact.artifact_id, artifact.version),
        entry,
      )
      if workspace_asset_matches(
          entry, project_id, normalized, kind, tag, include_deleted,
        ) {
        matching.push(entry)
      }
    }
  }
  matching.sort_by((left, right) => {
    right.artifact.created_at.compare(left.artifact.created_at)
  })
  let entries : Array[@workspace.WorkspaceAssetEntry] = []
  for index, entry in matching {
    if index >= offset && index < offset + limit {
      entries.push(entry)
    }
  }
  {
    contract: "mooncast.workspace-asset-library.v1",
    project_id,
    entries,
    total: matching.length(),
    offset,
    limit,
    has_more: offset + entries.length() < matching.length(),
    publication_authority: false,
  }
}

///|
pub async fn StudioService::tag_workspace_asset(
  self : StudioService,
  artifact_id : String,
  version : Int,
  request : WorkspaceAssetTagsRequest,
) -> @workspace.WorkspaceAssetEntry {
  guard request.tags.length() <= 32 &&
    request.tags.all(tag => {
      let trimmed = tag.trim()
      !trimmed.is_blank() &&
      trimmed.length() <= 48 &&
      !trimmed.contains("\u{0000}")
    }) else {
    raise Invalid(
      code="workspace_asset_tags_invalid",
      message="asset tags must be non-empty, at most 48 characters, and limited to 32",
    )
  }
  self.with_mutation_lock(() => {
    let current = self.workspace_asset_entry(artifact_id, version)
    let tags : Array[String] = []
    for tag in request.tags {
      let normalized = tag.trim().to_lower().to_owned()
      if !tags.contains(normalized) {
        tags.push(normalized)
      }
    }
    let updated = { ..current, tags, updated_at: now_string() }
    save_value(
      self.store,
      workspace_asset_entry_key(artifact_id, version),
      updated,
    )
    self.save_workspace_activity(
      workspace_activity(
        current.artifact.project_id,
        request.actor,
        "asset-tags-updated",
        @workspace.ArtifactTarget,
        artifact_id,
        tags.join(","),
        updated.updated_at,
      ),
    )
    updated
  })
}

///|
async fn StudioService::workspace_asset_is_referenced(
  self : StudioService,
  entry : @workspace.WorkspaceAssetEntry,
) -> Bool {
  for key in self.store.list_keys(prefix="workspace-share-", suffix=".json") {
    let share : @workspace.WorkspaceShare? = load_value(self.store, key)
    if share is Some(value) &&
      !value.revoked &&
      value.project_id == entry.artifact.project_id &&
      value.target_kind == @workspace.ArtifactTarget &&
      value.target_id == entry.artifact.artifact_id {
      return true
    }
  }
  for
    key in self.store.list_keys(
      prefix="workspace-graph-",
      suffix="-latest.json",
    ) {
    let graph : @workspace.WorkspaceGraph? = load_value(self.store, key)
    if graph is Some(value) &&
      value.project_id == entry.artifact.project_id &&
      value.to_json().stringify().contains(entry.artifact.artifact_id) {
      return true
    }
  }
  false
}

///|
pub async fn StudioService::delete_workspace_asset(
  self : StudioService,
  artifact_id : String,
  version : Int,
  request : WorkspaceAssetDeleteRequest,
) -> @workspace.WorkspaceAssetEntry {
  self.with_mutation_lock(() => {
    let current = self.workspace_asset_entry(artifact_id, version)
    guard !self.workspace_asset_is_referenced(current) else {
      raise Conflict(
        code="workspace_asset_in_use",
        message="asset is referenced by an active graph or share",
      )
    }
    let updated = { ..current, deleted: true, updated_at: now_string() }
    save_value(
      self.store,
      workspace_asset_entry_key(artifact_id, version),
      updated,
    )
    self.save_workspace_activity(
      workspace_activity(
        current.artifact.project_id,
        request.actor,
        "asset-hidden",
        @workspace.ArtifactTarget,
        artifact_id,
        "immutable evidence retained",
        updated.updated_at,
      ),
    )
    updated
  })
}
