///|
fn parameter_definition_named(
  definition : NodeDefinition,
  parameter_id : String,
) -> ParameterDefinition? {
  for parameter in definition.parameters {
    if parameter.parameter_id == parameter_id {
      return Some(parameter)
    }
  }
  None
}

///|
fn supplied_parameter_named(
  parameters : Array[NodeParameter],
  parameter_id : String,
) -> NodeParameter? {
  for parameter in parameters {
    if parameter.key == parameter_id {
      return Some(parameter)
    }
  }
  None
}

///|
fn parameter_value_matches(kind : ParameterValueKind, value : Json) -> Bool {
  match (kind, value) {
    (
      TextValue
      | AssetReferenceValue
      | ProviderValue
      | ModelValue,
      Json::String(_),
    ) => true
    (IntegerValue | NumberValue, Json::Number(_, ..)) => true
    (BooleanValue, Json::True | Json::False) => true
    (JsonValue, _) => true
    _ => false
  }
}

///|
fn parameter_numeric_value(value : Json) -> Double? {
  match value {
    Json::Number(number, ..) => Some(number)
    _ => None
  }
}

///|
fn parameter_option_matches(
  options : Array[ParameterOption],
  value : Json,
) -> Bool {
  if options.is_empty() {
    true
  } else {
    match value {
      Json::String(text) => options.any(option => option.value == text)
      _ => false
    }
  }
}

///|
fn parameter_bounds_match(
  definition : ParameterDefinition,
  value : Json,
) -> Bool {
  match parameter_numeric_value(value) {
    None => true
    Some(number) =>
      definition.minimum.map(bound => number >= bound).unwrap_or(true) &&
      definition.maximum.map(bound => number <= bound).unwrap_or(true)
  }
}

///|
fn parameter_definition_errors(
  definition : ParameterDefinition,
) -> Array[String] {
  let errors : Array[String] = []
  if definition.parameter_id.is_blank() {
    errors.push("parameter id must not be blank")
  }
  if definition.label.is_blank() {
    errors.push("parameter " + definition.parameter_id + " has no label")
  }
  match (definition.minimum, definition.maximum) {
    (Some(minimum), Some(maximum)) if minimum > maximum =>
      errors.push(
        "parameter " + definition.parameter_id + " has inverted bounds",
      )
    _ => ()
  }
  match definition.step {
    Some(step) if step <= 0.0 =>
      errors.push(
        "parameter " + definition.parameter_id + " has a non-positive step",
      )
    _ => ()
  }
  match definition.default_value {
    Some(value) if !parameter_value_matches(definition.value_kind, value) =>
      errors.push(
        "parameter " + definition.parameter_id + " has an invalid default type",
      )
    Some(value) if !parameter_option_matches(definition.options, value) =>
      errors.push(
        "parameter " + definition.parameter_id + " has an unlisted default",
      )
    Some(value) if !parameter_bounds_match(definition, value) =>
      errors.push(
        "parameter " + definition.parameter_id + " has an out-of-range default",
      )
    _ => ()
  }
  errors
}

///|
/// Validates declared creative parameters without rejecting legacy or reserved
/// graph metadata. Unknown keys remain visible as warnings and survive plan
/// freezing, so schema adoption is forwards-compatible.
pub fn validate_node_parameters(
  definition : NodeDefinition,
  supplied : Array[NodeParameter],
) -> NodeParameterValidation {
  let errors : Array[String] = []
  for declared in definition.parameters {
    errors.append(parameter_definition_errors(declared))
  }
  let warnings : Array[String] = []
  for
    parameter_id in duplicate_values(
      definition.parameters.map(parameter => parameter.parameter_id),
    ) {
    errors.push("duplicate parameter definition: " + parameter_id)
  }
  for declared in definition.parameters {
    let value = supplied_parameter_named(supplied, declared.parameter_id)
    if declared.required && value is None && declared.default_value is None {
      errors.push("missing required parameter: " + declared.parameter_id)
    }
    match value {
      Some(parameter) if !parameter_value_matches(
          declared.value_kind,
          parameter.value,
        ) =>
        errors.push(
          "parameter " + declared.parameter_id + " has the wrong type",
        )
      Some(parameter) if !parameter_option_matches(
          declared.options,
          parameter.value,
        ) =>
        errors.push(
          "parameter " + declared.parameter_id + " is not an allowed option",
        )
      Some(parameter) if !parameter_bounds_match(declared, parameter.value) =>
        errors.push(
          "parameter " + declared.parameter_id + " is outside its bounds",
        )
      _ => ()
    }
  }
  for parameter in supplied {
    if parameter_definition_named(definition, parameter.key) is None &&
      !parameter.key.has_prefix("workspace:") {
      warnings.push("undeclared parameter preserved: " + parameter.key)
    }
  }
  { valid: errors.is_empty(), errors, warnings }
}

///|
/// Returns the canonical parameter set used by execution. Explicit values win;
/// absent declared values are filled from data defaults; undeclared metadata is
/// retained. The stable key order makes graph digests reproducible.
pub fn materialize_node_parameters(
  definition : NodeDefinition,
  supplied : Array[NodeParameter],
) -> Array[NodeParameter] {
  let materialized = definition.parameters.fold(init=supplied.copy(), (
    values,
    declared,
  ) => {
    if values.any(parameter => parameter.key == declared.parameter_id) {
      values
    } else {
      match declared.default_value {
        Some(value) => {
          values.push({ key: declared.parameter_id, value })
          values
        }
        None => values
      }
    }
  })
  materialized.sort_by((left, right) => left.key.compare(right.key))
  materialized
}

///|
/// Purely expands declarative defaults into a frozen graph. Saved editable
/// graphs may stay concise while every execution plan remains fully explicit.
pub fn materialize_graph_parameters(
  graph : WorkspaceGraph,
  catalog : Array[NodeDefinition],
) -> WorkspaceGraph {
  {
    ..graph,
    nodes: graph.nodes.map(node => {
      match definition_named(catalog, node.definition_id) {
        Some(definition) =>
          {
            ..node,
            parameters: materialize_node_parameters(definition, node.parameters),
          }
        None => node
      }
    }),
  }
}
