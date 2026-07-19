///|
let artifact_sections : Array[String] = [
  "book_templates", "schemas", "workflows", "skills", "policies", "provider_ports",
  "migrations", "evaluations",
]

///|
fn object_string(value : Map[String, Json], key : String) -> String? {
  match value.get(key) {
    Some(Json::String(text)) => Some(text)
    _ => None
  }
}

///|
fn safe_relative_path(value : String) -> Bool {
  if value == "" || value.has_prefix("/") || value.contains("\\") {
    return false
  }
  for part in value.split("/") {
    if part == "" || part == "." || part == ".." {
      return false
    }
  }
  true
}

///|
fn reference_issues(
  location : String,
  section : String,
  reference : Json,
  seen_ids : Map[String, Unit],
  declared_schemas : Map[String, Unit],
  references : Array[(String, String)],
) -> Array[String] {
  let issues : Array[String] = []
  guard reference is Json::Object(value) else {
    issues.push("pack.json:\{location}: contract reference must be an object")
    return issues
  }
  let ref_id = object_string(value, "id")
  let ref_path = object_string(value, "path")
  match ref_id {
    None => issues.push("pack.json:\{location}: contract id is missing")
    Some(id) if seen_ids.contains(id) =>
      issues.push("pack.json:\{location}: duplicate contract id \{id}")
    Some(id) => seen_ids[id] = ()
  }
  match ref_path {
    None => issues.push("pack.json:\{location}: contract path is missing")
    Some(path) if !safe_relative_path(path) =>
      issues.push("pack.json:\{location}: unsafe or non-local path \{path}")
    Some(path) => {
      references.push((location, path))
      if section == "schemas" {
        if !path.has_prefix("schemas/") || !path.has_suffix(".schema.json") {
          issues.push(
            "pack.json:\{location}: schema path is outside schemas/: \{path}",
          )
        }
        match ref_id {
          Some(id) => {
            declared_schemas[id] = ()
            if path != "schemas/\{id}.schema.json" {
              issues.push(
                "pack.json:\{location}: schema id/path mapping is not exact",
              )
            }
          }
          None => ()
        }
      }
    }
  }
  issues
}

///|
fn manifest_shape_issues(
  manifest : Json,
) -> (Array[String], Array[(String, String)]) {
  let issues : Array[String] = []
  let references : Array[(String, String)] = []
  guard manifest is Json::Object(root) else {
    issues.push("pack.json: manifest root must be an object")
    return (issues, references)
  }
  if object_string(root, "id") != Some("mooncast") ||
    object_string(root, "product_id") != Some("mooncast") {
    issues.push("pack.json: id and product_id must both be mooncast")
  }
  let declared_schemas : Map[String, Unit] = {}
  for section in artifact_sections {
    let seen_ids : Map[String, Unit] = {}
    match root.get(section) {
      Some(Json::Array(values)) =>
        for index, reference in values {
          issues.push_iter(
            reference_issues(
              "\{section}[\{index}]",
              section,
              reference,
              seen_ids,
              declared_schemas,
              references,
            ).iter(),
          )
        }
      _ =>
        issues.push("pack.json:\{section}: contract section must be an array")
    }
  }
  let uninstall_seen : Map[String, Unit] = {}
  match root.get("uninstall_contract") {
    Some(reference) =>
      issues.push_iter(
        reference_issues(
          "uninstall_contract", "uninstall_contract", reference, uninstall_seen,
          declared_schemas, references,
        ).iter(),
      )
    None =>
      issues.push(
        "pack.json:uninstall_contract: contract reference must be an object",
      )
  }
  let tool_ids : Map[String, Unit] = {}
  match root.get("tools") {
    Some(Json::Array(tools)) =>
      for index, tool in tools {
        let location = "pack.json:tools[\{index}]"
        match tool {
          Json::Object(value) => {
            match object_string(value, "id") {
              None => issues.push("\{location}: id is missing")
              Some(id) if tool_ids.contains(id) =>
                issues.push("\{location}: duplicate tool id \{id}")
              Some(id) => tool_ids[id] = ()
            }
            if object_string(value, "owner_product") != Some("mooncast") {
              issues.push("\{location}: tool is not owned by mooncast")
            }
            for field in ["input_schema_id", "output_schema_id"] {
              match object_string(value, field) {
                Some(id) if declared_schemas.contains(id) => ()
                _ =>
                  issues.push("\{location}: \{field} is not a declared schema")
              }
            }
            match value.get("evidence_outputs") {
              Some(Json::Array(outputs)) =>
                for output in outputs {
                  match output {
                    Json::String(path) if safe_relative_path(path) => ()
                    _ =>
                      issues.push(
                        "\{location}: evidence outputs must be safe pack-relative paths",
                      )
                  }
                }
              _ =>
                issues.push(
                  "\{location}: evidence outputs must be safe pack-relative paths",
                )
            }
          }
          _ => issues.push("\{location}: tool must be an object")
        }
      }
    _ => issues.push("pack.json:tools: must be an array")
  }
  (issues, references)
}

///|
async fn path_has_symlink(root : String, relative : String) -> Bool {
  let mut current = root
  for part in relative.split("/") {
    current = current + "/" + part.to_owned()
    if @fs.exists(current) && @fs.kind(current, follow_symlink=false) is SymLink {
      return true
    }
  }
  false
}

///|
async fn validate_manifest(root : String) -> Array[String] {
  let issues : Array[String] = []
  let path = root + "/pack.json"
  guard @fs.exists(path) && @fs.kind(path, follow_symlink=false) is Regular else {
    return ["pack.json: missing, non-regular, or symlinked static manifest"]
  }
  let text = @fs.read_file(path).text() catch {
    error => return ["pack.json: unreadable strict UTF-8: \{to_repr(error)}"]
  }
  let duplicates : Array[String] = duplicate_json_keys(text) catch {
    error => {
      issues.push(
        "pack.json: duplicate-key scan failed closed: \{to_repr(error)}",
      )
      []
    }
  }
  for key in duplicates {
    issues.push("pack.json: duplicate JSON key: \{key}")
  }
  let static_manifest = @json.parse(text) catch {
    error => {
      issues.push("pack.json: invalid strict JSON: \{to_repr(error)}")
      return issues
    }
  }
  let compiled_manifest = @json.parse(
    @pack.encode_manifest(@mooncast.manifest()),
  ) catch {
    error => {
      issues.push("compiled manifest is invalid JSON: \{to_repr(error)}")
      return issues
    }
  }
  if static_manifest != compiled_manifest {
    issues.push(
      "pack.json: static manifest differs from the compiled MoonBit manifest",
    )
  }
  let (shape_issues, references) = manifest_shape_issues(static_manifest)
  issues.push_iter(shape_issues.iter())
  for reference in references {
    let (location, relative) = reference
    let candidate = root + "/" + relative
    if path_has_symlink(root, relative) {
      issues.push(
        "pack.json:\{location}: reference crosses a symlink: \{relative}",
      )
    } else if !@fs.exists(candidate) {
      issues.push(
        "pack.json:\{location}: referenced file does not exist: \{relative}",
      )
    } else if !(@fs.kind(candidate, follow_symlink=false) is Regular) {
      issues.push(
        "pack.json:\{location}: referenced path is not a regular file: \{relative}",
      )
    } else {
      let resolved = @fs.realpath(candidate)
      if resolved != root && !resolved.has_prefix(root + "/") {
        issues.push(
          "pack.json:\{location}: reference is not pack-owned: \{relative}",
        )
      }
    }
  }
  issues
}
