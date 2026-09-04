///|
fn parameter_option(value : String, label : String) -> ParameterOption {
  { value, label }
}

///|
fn parameter_definition(
  parameter_id : String,
  label : String,
  description : String,
  value_kind : ParameterValueKind,
  control : ParameterControl,
  default_value : Json?,
  required : Bool,
  advanced : Bool,
  minimum : Double?,
  maximum : Double?,
  step : Double?,
  options : Array[ParameterOption],
) -> ParameterDefinition {
  {
    parameter_id,
    label,
    description,
    value_kind,
    control,
    default_value,
    required,
    advanced,
    minimum,
    maximum,
    step,
    options,
  }
}

///|
fn text_parameter(
  parameter_id : String,
  label : String,
  description : String,
  default_value : String,
  multiline : Bool,
  advanced? : Bool = false,
) -> ParameterDefinition {
  parameter_definition(
    parameter_id,
    label,
    description,
    TextValue,
    if multiline {
      TextAreaControl
    } else {
      TextFieldControl
    },
    Some(default_value.to_json()),
    false,
    advanced,
    None,
    None,
    None,
    [],
  )
}

///|
fn integer_parameter(
  parameter_id : String,
  label : String,
  description : String,
  default_value : Int,
  minimum : Double,
  maximum : Double,
  step : Double,
  slider? : Bool = false,
  advanced? : Bool = false,
) -> ParameterDefinition {
  parameter_definition(
    parameter_id,
    label,
    description,
    IntegerValue,
    if slider {
      SliderControl
    } else {
      NumberFieldControl
    },
    Some(default_value.to_json()),
    false,
    advanced,
    Some(minimum),
    Some(maximum),
    Some(step),
    [],
  )
}

///|
fn boolean_parameter(
  parameter_id : String,
  label : String,
  description : String,
  default_value : Bool,
  advanced? : Bool = false,
) -> ParameterDefinition {
  parameter_definition(
    parameter_id,
    label,
    description,
    BooleanValue,
    CheckboxControl,
    Some(default_value.to_json()),
    false,
    advanced,
    None,
    None,
    None,
    [],
  )
}

///|
fn select_parameter(
  parameter_id : String,
  label : String,
  description : String,
  default_value : String,
  value_kind : ParameterValueKind,
  options : Array[ParameterOption],
  advanced? : Bool = false,
) -> ParameterDefinition {
  parameter_definition(
    parameter_id,
    label,
    description,
    value_kind,
    SelectControl,
    Some(default_value.to_json()),
    false,
    advanced,
    None,
    None,
    None,
    options,
  )
}

///|
fn asset_parameter() -> ParameterDefinition {
  parameter_definition(
    "asset_ref",
    "Asset",
    "Choose a versioned workspace asset.",
    AssetReferenceValue,
    AssetPickerControl,
    None,
    false,
    false,
    None,
    None,
    None,
    [],
  )
}

///|
fn provider_parameter() -> ParameterDefinition {
  parameter_definition(
    "provider",
    "Provider",
    "Optional provider override; an empty value uses governed routing.",
    ProviderValue,
    ProviderPickerControl,
    Some("".to_json()),
    false,
    true,
    None,
    None,
    None,
    [],
  )
}

///|
fn model_parameter() -> ParameterDefinition {
  parameter_definition(
    "model",
    "Model",
    "Optional model override within the selected provider route.",
    ModelValue,
    ModelPickerControl,
    Some("".to_json()),
    false,
    true,
    None,
    None,
    None,
    [],
  )
}

///|
fn generation_parameters() -> Array[ParameterDefinition] {
  [
    text_parameter(
      "prompt", "Prompt", "Creative direction supplied to the generation operation.",
      "", true,
    ),
    select_parameter(
      "modality",
      "Modality",
      "Primary content form to generate.",
      "image",
      TextValue,
      [
        parameter_option("image", "Image"),
        parameter_option("video", "Video"),
        parameter_option("audio", "Audio"),
        parameter_option("copy", "Copy"),
      ],
    ),
    integer_parameter(
      "variant_count",
      "Variants",
      "Number of alternatives to keep for comparison.",
      4,
      1.0,
      8.0,
      1.0,
      slider=true,
    ),
    select_parameter(
      "aspect_ratio",
      "Aspect ratio",
      "Target composition ratio.",
      "16:9",
      TextValue,
      [
        parameter_option("16:9", "Landscape 16:9"),
        parameter_option("9:16", "Vertical 9:16"),
        parameter_option("1:1", "Square 1:1"),
        parameter_option("4:5", "Portrait 4:5"),
      ],
    ),
    provider_parameter(),
    model_parameter(),
    integer_parameter(
      "seed",
      "Seed",
      "Deterministic seed when the provider supports one; zero means automatic.",
      0,
      0.0,
      2147483647.0,
      1.0,
      advanced=true,
    ),
  ]
}

///|
fn builtin_parameters(definition_id : String) -> Array[ParameterDefinition] {
  match definition_id {
    "workspace.brief-input" =>
      [
        text_parameter(
          "brief", "Creative brief", "Describe the goal, audience, message, style, and constraints.",
          "", true,
        ),
      ]
    "workspace.asset-input" => [asset_parameter()]
    "workspace.media-normalize" =>
      [
        select_parameter(
          "video_codec",
          "Video codec",
          "Normalize incompatible video streams to this codec.",
          "h264",
          TextValue,
          [
            parameter_option("h264", "H.264"),
            parameter_option("hevc", "HEVC"),
            parameter_option("copy", "Copy compatible streams"),
          ],
        ),
        select_parameter(
          "audio_codec",
          "Audio codec",
          "Normalize incompatible audio streams to this codec.",
          "aac",
          TextValue,
          [
            parameter_option("aac", "AAC"),
            parameter_option("copy", "Copy compatible streams"),
          ],
        ),
      ]
    "workspace.media-concat" =>
      [
        select_parameter(
          "container",
          "Container",
          "Container used for the combined master.",
          "mp4",
          TextValue,
          [parameter_option("mp4", "MP4"), parameter_option("mov", "MOV")],
        ),
        boolean_parameter(
          "fast_start", "Web fast start", "Move container metadata to the front for progressive playback.",
          true,
        ),
      ]
    "workspace.control.generate-variants" =>
      [
        integer_parameter(
          "variant_count",
          "Variants",
          "Number of bounded branches to create.",
          4,
          1.0,
          8.0,
          1.0,
          slider=true,
        ),
      ]
    "workspace.control.select" =>
      [
        select_parameter(
          "strategy",
          "Selection strategy",
          "How a single result is selected from candidate assets.",
          "manual",
          TextValue,
          [
            parameter_option("manual", "Human selection"),
            parameter_option("score", "Highest score"),
            parameter_option("first", "First result"),
          ],
        ),
      ]
    "workspace.control.policy-gate" =>
      [
        text_parameter(
          "policy_id", "Policy", "Named policy evaluated before downstream execution.",
          "", false,
        ),
      ]
    "workspace.control.human-approval" =>
      [
        select_parameter(
          "decision",
          "Decision",
          "Named human decision recorded in the run ledger.",
          "pending",
          TextValue,
          [
            parameter_option("pending", "Pending"),
            parameter_option("approve", "Approve"),
            parameter_option("reject", "Reject"),
          ],
        ),
        text_parameter(
          "note", "Decision note", "Reason captured with the decision.", "", true,
        ),
      ]
    "workspace.control.subgraph" =>
      [
        text_parameter(
          "capsule_id", "Capsule", "Installed capsule identifier.", "", false,
        ),
        integer_parameter(
          "capsule_version", "Version", "Pinned capsule version.", 1, 1.0, 1000000.0,
          1.0,
        ),
      ]
    _ => []
  }
}

///|
/// Manifest declarations remain the capability source of truth. This pure
/// projection adds reusable creative controls when the declared input contract
/// is known, and a structured request editor for every other capability.
fn parameters_for_tool(
  tool : @pack.ToolDeclaration,
) -> Array[ParameterDefinition] {
  if tool.input_schema_id == "generation-request" ||
    tool.id.contains("generate") {
    generation_parameters()
  } else if tool.input_schema_id == "creative-revision-request" {
    [
      text_parameter(
        "instruction", "Revision instruction", "Describe the specific creative change to apply.",
        "", true,
      ),
      asset_parameter(),
      provider_parameter(),
      model_parameter(),
    ]
  } else {
    [
      parameter_definition(
        "request",
        "Structured request",
        "Advanced JSON input conforming to " + tool.input_schema_id + ".",
        JsonValue,
        JsonEditorControl,
        Some(Json::empty_object()),
        false,
        true,
        None,
        None,
        None,
        [],
      ),
    ]
  }
}
