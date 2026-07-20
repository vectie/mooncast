///|
/// Gate receipts must represent a named human decision. Product/runtime labels
/// are deliberately rejected even when all underlying evidence is ready.
fn gate_reviewer_issues(actor : String, role : String) -> Array[String] {
  let issues : Array[String] = []
  if actor.trim() == "" {
    issues.push("named actor is required")
  }
  let normalized_role = role.trim().to_lower().to_owned()
  if normalized_role == "" {
    issues.push("named human role is required")
  } else if [
      "automation", "agent", "moonclaw", "moonflow", "provider-execution-host", "workflow-orchestrator",
    ].contains(normalized_role) {
    issues.push("runtime or automation roles cannot approve a production gate")
  }
  issues
}
