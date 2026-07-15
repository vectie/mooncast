///|
test "publication requires rights safety provenance and human approval" {
  let incomplete : DeliveryGate = {
    rights_cleared: true,
    safety_passed: true,
    human_approved: false,
    provenance_complete: true,
  }
  assert_false(publication_ready(Packaged, incomplete))
  assert_true(
    publication_ready(Packaged, { ..incomplete, human_approved: true }),
  )
}

///|
test "Mooncast manifest validates and all external effects require review" {
  let value = manifest()
  assert_true(@pack.validate_manifest(value).ok)
  assert_false(@pack.has_authority(value, PhysicalEffect))
  assert_true(
    value.tools
    .filter(tool => tool.authority == ExternalEffect)
    .all(tool => tool.review_required),
  )
}

///|
async test "checked-in Mooncast repository is an installable pack" {
  let inspection = @installer.inspect_source(".")
  assert_true(inspection.plan.validation.ok)
  assert_true(inspection.issues.is_empty())
  assert_eq(
    @pack.encode_manifest(inspection.manifest),
    @pack.encode_manifest(manifest()),
  )
}
