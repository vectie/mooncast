///|
fn annotation_context(value : ClientProjection) -> String {
  [
    value.portal.portal_id,
    value.project.project_id,
    value.binding.master_sha256,
    value.binding.build_id,
    value.binding.build_digest,
    value.binding.delivery_digest,
  ]
  .to_json()
  .stringify()
}

///|
fn save_annotation_draft(model : Model) -> Map[String, AnnotationDraft] {
  let drafts = model.annotation_drafts.copy()
  if model.projection is Some(value) {
    drafts[annotation_context(value)] = model.annotation
  }
  drafts
}

///|
fn next_client_operation(
  model : Model,
  value : ClientProjection,
) -> ClientOperation {
  {
    portal_generation: model.portal_generation,
    operation_id: model.operation_sequence + 1,
    context: annotation_context(value),
  }
}

///|
fn operation_is_current(model : Model, operation : ClientOperation) -> Bool {
  model.portal_generation == operation.portal_generation &&
  model.projection.map(annotation_context) == Some(operation.context)
}

///|
fn empty_annotation() -> AnnotationDraft {
  { timecode: "0.000", author: "", body: "", }
}
