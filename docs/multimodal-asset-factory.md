# Multimodal reusable asset factory

Mooncast now treats reusable assets as a governed production stage between the
approved bible/script (G2) and dependent shot generation. A versioned plan can
describe characters, locations, props, voices, music, motion, images, and text.
Each specification binds exact MoonWiki intent evidence, rights references,
continuity identity, provider/model/data-class routing, one to four variants,
one to five attempts, a cost ceiling, and the exact dependent shot IDs.

The Studio **Asset Factory** workbench records and approves the plan, explicitly
authorizes provider execution, runs bounded variants, records technical,
identity, continuity, rights, and safety QC, selects one immutable output per
asset version, and binds approved versions to shots. If a current asset plan
has a dependency, routed shot generation is rejected until its exact approved
asset binding exists. Provider requests then carry those exact immutable assets
and the production coordinator verifies the same request before execution.

The provider port supports text, image, video, voice, and music capabilities.
Credentials remain host secret references and every real provider call requires
explicit named authority. The checked-in deterministic adapter emits typed,
validation-only artifacts for lifecycle tests; it is never a commercial media
fallback and records `network_effect_performed=false`.

All plans, decisions, variants, QC findings, approvals, and shot bindings are
Mooncast pack-local durable evidence. None grants publication authority, and no
MoonSuite core branch or domain-specific runtime behavior is introduced.
