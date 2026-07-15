///|
fn contract(id : String, path : String) -> @pack.ContractRef {
  @pack.contract_ref(id, "1.0.0", path)
}

///|
fn schema(id : String) -> @pack.ContractRef {
  contract(id, "schemas/" + id + ".schema.json")
}

///|
fn tool(
  id : String,
  input : String,
  output : String,
  authority : @pack.AuthorityClass,
  evidence_outputs : Array[String],
  review_required? : Bool = false,
) -> @pack.ToolDeclaration {
  @pack.tool_declaration(
    id,
    "mooncast",
    input,
    output,
    authority,
    evidence_outputs~,
    review_required~,
  )
}

///|
pub fn manifest() -> @pack.MoonPackManifest {
  {
    id: "mooncast",
    version: "0.1.0",
    display_name: "Mooncast AIGC Campaign Studio",
    product_id: "mooncast",
    kind: DomainPack,
    required_runtime_extensions: ["moonclaw"],
    book_templates: [contract("campaign-book", "book/campaign-book.md")],
    schemas: [
      schema("creative-brief"),
      schema("generation-request"),
      schema("asset-provenance"),
      schema("review-decision"),
      schema("delivery-package"),
      schema("publication-receipt"),
    ],
    tools: [
      tool(
        "brief.validate",
        "creative-brief",
        "creative-brief",
        SandboxExecution,
        ["records/briefs"],
      ),
      tool(
        "asset.generate",
        "generation-request",
        "asset-provenance",
        ExternalEffect,
        ["raw/generations"],
        review_required=true,
      ),
      tool(
        "asset.review",
        "asset-provenance",
        "review-decision",
        WorkspaceMutation,
        ["records/reviews"],
        review_required=true,
      ),
      tool(
        "delivery.package",
        "review-decision",
        "delivery-package",
        SandboxExecution,
        ["records/deliveries"],
      ),
      tool(
        "campaign.publish",
        "delivery-package",
        "publication-receipt",
        ExternalEffect,
        ["records/publications"],
        review_required=true,
      ),
    ],
    workflows: [contract("brief-to-delivery", "workflows/brief-to-delivery.md")],
    skills: [contract("campaign-producer", "skills/campaign-producer.md")],
    policies: [
      contract("rights-clearance", "policies/rights-clearance.md"),
      contract("content-safety", "policies/content-safety.md"),
      contract("content-labeling", "policies/content-labeling.md"),
      contract("human-review", "policies/human-review.md"),
    ],
    provider_ports: [
      contract("model-generation", "providers/model-generation.port.md"),
      contract("media-storage", "providers/media-storage.port.md"),
      contract("publishing", "providers/publishing.port.md"),
    ],
    schedules: [],
    app_entrypoints: [
      @pack.app_entrypoint(
        "campaign-studio", "/apps/mooncast/studio", "campaign-operator",
      ),
    ],
    migrations: [contract("mooncast-install", "migrations/install.md")],
    evaluations: [
      contract("delivery-acceptance", "evaluations/delivery-acceptance.md"),
    ],
    uninstall_contract: Some(contract("mooncast-uninstall", "UNINSTALL.md")),
  }
}
