///|
fn normalized_issues(values : Array[String]) -> Array[String] {
  values.sort()
  let output : Array[String] = []
  let mut previous : String? = None
  for value in values {
    if previous != Some(value) {
      output.push(value)
      previous = Some(value)
    }
  }
  output
}

///|
pub async fn scan(root : String) -> Array[String] {
  let resolved = @fs.realpath(root)
  guard @fs.kind(resolved, follow_symlink=false) is Directory else {
    return ["pack boundary root is not a directory: \{resolved}"]
  }
  normalized_issues(
    [..validate_manifest(resolved), ..validate_sources(resolved)],
  )
}
