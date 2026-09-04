///|
let excluded_directories : Array[String] = [
  ".git", ".mooncakes", ".moonsuite", ".tools", "_build", "dist", "node_modules",
  "target",
]

///|
let generic_core_names : Array[String] = [
  "moonsuite", "moonflow", "moonbook", "moonfish",
]

///|
let source_suffixes : Array[String] = [
  ".mbt", ".js", ".mjs", ".cjs", ".ts", ".tsx",
]

///|
let config_names : Array[String] = [
  "moon.mod", "moon.pkg", "package.json", "package-lock.json", "Cargo.toml",
]

///|
fn path_name(path : String) -> String {
  let parts = path.split("/").collect()
  if parts.is_empty() {
    path
  } else {
    parts[parts.length() - 1].to_owned()
  }
}

///|
fn is_source_or_config(path : String) -> Bool {
  let name = path_name(path)
  config_names.contains(name) ||
  source_suffixes.any(suffix => name.has_suffix(suffix))
}

///|
async fn contains_source_tree(directory : String) -> Bool {
  let names = @fs.readdir(
    directory,
    include_hidden=true,
    include_special=false,
    sort=true,
  )
  for name in names {
    if excluded_directories.contains(name) {
      continue
    }
    let child = directory + "/" + name
    match @fs.kind(child, follow_symlink=false) {
      Regular if is_source_or_config(name) => return true
      Directory if contains_source_tree(child) => return true
      _ => ()
    }
  }
  false
}

///|
fn imported_generic_core(line : String) -> Bool {
  let normalized = line.trim().to_owned().to_lower()
  for name in generic_core_names {
    if normalized.has_prefix("from \{name}") ||
      normalized.has_prefix("import \{name}") ||
      normalized.contains("\"\{name}/") ||
      normalized.contains("'\{name}/") ||
      normalized.contains("/\{name}/") ||
      normalized.contains("/\{name}\"") ||
      normalized.contains("/\{name}'") {
      return true
    }
  }
  false
}

///|
fn local_script_escape(line : String) -> Bool {
  let normalized = line.trim().to_owned()
  (
    normalized.has_prefix("import ") ||
    normalized.contains(" from ") ||
    normalized.contains("require(")
  ) &&
  (
    normalized.contains("\"../") ||
    normalized.contains("'../") ||
    normalized.contains("\"/") ||
    normalized.contains("'/")
  )
}

///|
fn workspace_name_after(line : String, marker : String) -> String? {
  let pieces = line.split(marker).collect()
  guard pieces.length() >= 2 else { None }
  let tail = pieces[1].split("/").collect()
  if tail.is_empty() || tail[0] == "" {
    None
  } else {
    Some(tail[0].to_owned())
  }
}

///|
fn has_sibling_workspace_path(text : String, root_name : String) -> Bool {
  for line in text.split("\n") {
    let owned = line.to_owned()
    let filesystem_absolute = owned.contains("/Users/") ||
      owned.contains("/home/") ||
      owned.contains("/Volumes/") ||
      owned.contains("/private/")
    if !filesystem_absolute {
      continue
    }
    for marker in ["/" + "Workspace/", "/" + "workspace/"] {
      match workspace_name_after(owned, marker) {
        Some(name) if name.to_lower() != root_name.to_lower() => return true
        _ => ()
      }
    }
  }
  false
}

///|
fn is_test_source(relative : String) -> Bool {
  relative.split("/").any(part => part == "tests") ||
  relative.has_suffix("_test.mbt") ||
  relative.has_suffix("_wbtest.mbt")
}

///|
fn source_text_issues(
  relative : String,
  text : String,
  root_name : String,
) -> Array[String] {
  let issues : Array[String] = []
  let name = path_name(relative)
  if !is_test_source(relative) && has_sibling_workspace_path(text, root_name) {
    issues.push("\{relative}: absolute sibling workspace path is forbidden")
  }
  if config_names.contains(name) &&
    (
      text.contains("../") ||
      text.contains("= \"/") ||
      text.contains("= '/") ||
      text.contains(": \"/") ||
      text.contains(": '/")
    ) {
    issues.push("\{relative}: local dependency/import escapes the pack")
  }
  if [".js", ".mjs", ".cjs", ".ts", ".tsx"].any(suffix => {
      name.has_suffix(suffix)
    }) {
    for line in text.split("\n") {
      let owned = line.to_owned()
      if imported_generic_core(owned) {
        issues.push(
          "\{relative}: direct generic-core or Moonfish script import",
        )
        break
      }
      if local_script_escape(owned) {
        issues.push("\{relative}: local script import path escapes the pack")
        break
      }
    }
  } else if name == "moon.mod" || name == "moon.pkg" {
    for line in text.split("\n") {
      if imported_generic_core(line.to_owned()) {
        issues.push(
          "\{relative}: direct generic-core or Moonfish MoonBit import",
        )
        break
      }
    }
  }
  issues
}

///|
async fn scan_source_tree(
  root : String,
  relative : String,
  root_name : String,
  issues : Array[String],
) -> Unit {
  let directory = if relative == "" { root } else { root + "/" + relative }
  let names = @fs.readdir(
    directory,
    include_hidden=true,
    include_special=false,
    sort=true,
  )
  for name in names {
    if excluded_directories.contains(name) {
      continue
    }
    let child_relative = if relative == "" {
      name
    } else {
      relative + "/" + name
    }
    let child = root + "/" + child_relative
    let kind = @fs.kind(child, follow_symlink=false)
    match kind {
      Directory => {
        if generic_core_names.contains(name.to_lower()) &&
          contains_source_tree(child) {
          issues.push(
            "\{child_relative}: embedded generic-core or Moonfish source tree",
          )
        }
        scan_source_tree(root, child_relative, root_name, issues)
      }
      Regular if is_source_or_config(child_relative) => {
        let text : String? = Some(@fs.read_file(child).text()) catch {
          error => {
            issues.push(
              "\{child_relative}: source is not readable strict UTF-8: \{Repr(error)}",
            )
            None
          }
        }
        match text {
          Some(value) =>
            issues.push_iter(
              source_text_issues(child_relative, value, root_name).iter(),
            )
          None => ()
        }
      }
      SymLink if is_source_or_config(child_relative) => {
        let resolved : String? = Some(@fs.realpath(child)) catch {
          error => {
            issues.push(
              "\{child_relative}: source symlink cannot be resolved: \{Repr(error)}",
            )
            None
          }
        }
        match resolved {
          Some(value) if value != root && !value.has_prefix(root + "/") =>
            issues.push("\{child_relative}: source symlink escapes the pack")
          _ => ()
        }
      }
      _ => ()
    }
  }
}

///|
async fn validate_sources(root : String) -> Array[String] {
  let issues : Array[String] = []
  scan_source_tree(root, "", path_name(root), issues)
  issues
}
