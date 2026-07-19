///|
pub fn exact_approval(
  artifact : CreativeArtifact?,
  decisions : Array[CreativeDecision],
) -> Bool {
  match artifact {
    None => false
    Some(current) =>
      decisions.any(decision => {
        decision.artifact == current.reference &&
        decision.decision == "approved" &&
        decision.actor != "" &&
        decision.role != ""
      })
  }
}

///|
pub fn current_artifact(
  artifacts : Array[CreativeArtifact],
  kind : ArtifactKind,
) -> CreativeArtifact? {
  let mut found : CreativeArtifact? = None
  for artifact in artifacts {
    if artifact.kind == kind {
      match found {
        None => found = Some(artifact)
        Some(previous) =>
          if artifact.reference.version > previous.reference.version {
            found = Some(artifact)
          }
      }
    }
  }
  found
}

///|
pub fn artifact_bindings_current(
  artifact : CreativeArtifact,
  artifacts : Array[CreativeArtifact],
) -> Bool {
  artifact.dependency_digests.all(digest => {
    artifacts.any(candidate => candidate.reference.digest == digest)
  })
}

///|
/// Returns all downstream creative products made stale by a revision.
pub fn invalidation_for(changed : CreativeArtifact) -> DependencyInvalidation {
  let (invalidated_kinds, from_gate) = match changed.kind {
    Brief =>
      (
        [RightsLedger, IpBible, Script, ClaimsLedger, Storyboard, Animatic],
        "G0",
      )
    RightsLedger =>
      ([IpBible, Script, ClaimsLedger, Storyboard, Animatic], "G1")
    IpBible => ([Script, ClaimsLedger, Storyboard, Animatic], "G1")
    Script => ([ClaimsLedger, Storyboard, Animatic], "G2")
    ClaimsLedger => ([Storyboard, Animatic], "G2")
    Storyboard => ([Animatic], "G2")
    Animatic => ([], "G2")
  }
  {
    changed: changed.reference,
    invalidated_kinds,
    from_gate,
    reason: changed.kind.to_string() + " revised",
  }
}

///|
pub fn artifact_revision_valid(
  artifact : CreativeArtifact,
  existing : Array[CreativeArtifact],
) -> Bool {
  if artifact.reference.id == "" ||
    artifact.reference.version < 1 ||
    artifact.reference.digest == "" ||
    artifact.content.trim() == "" {
    return false
  }
  match current_artifact(existing, artifact.kind) {
    None => artifact.reference.version == 1
    Some(previous) =>
      artifact.reference.id == previous.reference.id &&
      artifact.reference.version == previous.reference.version + 1 &&
      artifact.reference.digest != previous.reference.digest
  }
}

///|
pub fn creative_decision_valid(
  artifact : CreativeArtifact?,
  decision : CreativeDecision,
) -> Bool {
  match artifact {
    None => false
    Some(value) =>
      decision.artifact == value.reference &&
      (
        decision.decision == "approved" ||
        decision.decision == "rejected" ||
        decision.decision == "revision-requested"
      ) &&
      decision.actor != "" &&
      decision.role != "" &&
      decision.decided_at != ""
  }
}

///|
pub fn artifact_for_reference(
  artifacts : Array[CreativeArtifact],
  reference : @project.VersionRef,
) -> CreativeArtifact? {
  for artifact in artifacts {
    if artifact.reference == reference {
      return Some(artifact)
    }
  }
  None
}

///|
pub fn creative_decision_is_current(
  artifacts : Array[CreativeArtifact],
  decision : CreativeDecision,
) -> Bool {
  match artifact_for_reference(artifacts, decision.artifact) {
    None => false
    Some(found) =>
      creative_decision_valid(current_artifact(artifacts, found.kind), decision)
  }
}
