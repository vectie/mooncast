# Third-iteration cfy feature comparison

Status: feature audit, 2026-09-04

## Scope

This audit compares Mooncast at `70be9998ca34e9e74c39215d85409bfda383759b`
with the local cfy/ComfyUI checkout at
`e80c1570b6b44a2557d5d8e341e05782d18c9bbb`.

The comparison is deliberately about product capability: what a creator,
producer, editor, reviewer, client, or agent can accomplish. It excludes
packaging, signing, security hardening, deployment, operational resilience,
and similar release-engineering concerns.

The central conclusion is:

> Mooncast has the stronger governed creative-production control plane;
> cfy has the stronger executable creative-compute engine and ecosystem.

Mooncast should not become a clone of cfy. It should preserve its production,
rights, review, delivery, and commercial model while adding a cfy-like
creative-compute layer beneath high-level production workflows.

## Evidence snapshot

Mooncast currently declares:

- 97 pack tools;
- 147 schemas;
- 59 workspace-mutation tools;
- 18 sandbox-execution tools;
- 10 observation tools;
- 7 external-effect tools; and
- 3 cognitive-maintenance tools.

The cfy checkout contains:

- 134 `comfy_extras/nodes_*.py` feature modules;
- 39 `comfy_api_nodes/nodes_*.py` partner-provider modules; and
- 89 checked-in workflow blueprints.

These counts are not direct equivalents. They reveal the difference in product
shape: Mooncast's surface is broad across the production lifecycle, whereas
cfy's surface is deep inside generation and transformation.

The rendered Mooncast workspace exposes two installed recipes—Combine videos
and Brief to generated delivery—plus five manifest-backed outcome labels. Its
main canvas foregrounds typed ports, run state, ownership, authority, caching,
review, and publication boundaries. That is valuable production information,
but the surface is still more status-forward than content-forward: generated
frames, contact sheets, waveforms, variants, and intermediate previews are not
yet the primary material of the graph.

## Detailed feature comparison

| Feature | Mooncast | cfy | Assessment |
| --- | --- | --- | --- |
| Visual graph editing | Typed connections, pointer movement, zoom, edge reconnection, copy/paste, grouping, mute, bypass, collapse, undo/redo and auto-layout | Mature node-canvas conventions, extensive keyboard operations and a large ecosystem designed around graph authoring | cfy leads in authoring depth; Mooncast has the correct foundation |
| Node parameters | Generic versioned key/value parameters supporting text, number, Boolean and JSON | Node-declared controls with defaults, ranges, sliders, enums, media controls, advanced fields, tooltips and remotely supplied choices | Major cfy advantage |
| Node abstraction | High-level production operations, assets, review gates and bounded controls | Fine-grained loaders, models, conditioning, samplers, generators, transforms and output nodes | The systems currently operate at different levels |
| Content generation | Provider contracts for text, image, video, voice and music | Extensive local and partner-backed text, image, video, audio and 3D generation | Major cfy advantage |
| Provider experience | Routing plans, permissions, cost limits, model choices, provider constraints and evidence receipts | Directly usable partner nodes across 39 provider modules | Mooncast governs providers better; cfy exposes much more ready-to-use generation |
| Local creative processing | Video concat, editor rendering, preview, analysis, QC and post-processing paths | Broad local image, audio, video, model, latent, mask, compositing and utility operations | cfy leads in breadth |
| Video editing | Multi-track timeline, trim, split, ripple, snapping, frame adjustments, transitions, overlays, masks, keyframes, speed curves and audio mixing | Graph operations for creating, slicing, trimming, cropping and saving video | Mooncast clearly leads as a nonlinear editor |
| Image editing | Artifact comparison and provider-backed image contracts, with limited native graph editing | Crop, mask, composite, upscale, filters, color, segmentation, background removal, tiling and model-backed editing | Major cfy advantage |
| Audio creation and editing | Voice/music/SFX production concepts, editor audio layers, volume, pan and mute | TTS, voice cloning, speech-to-text, recording, generation, trim, channels, concat, merge and EQ | cfy leads in direct creative capability |
| 3D | Outside the present Mooncast product focus | 3D generation, mesh processing, texturing, splats and export | cfy advantage, but low Mooncast priority |
| Model experimentation | Production-level provider/model routing | Checkpoints, LoRAs, ControlNets, VAEs, samplers, conditioning, merging, training and patching | cfy leads; Mooncast should adopt only production-relevant parts |
| Partial execution | Frozen selected-output plans and content-addressed cache keys | Output-driven execution and dirty-subgraph re-execution | Similar concept; cfy is more complete as a creative loop |
| Run history | Durable frozen graph, node state, attempts, retries, outputs and evidence | Prompt queue, execution history, cache events and node output events | Mooncast is stronger as a production record |
| Live creative feedback | Durable state/progress values, run events and output references | Per-node progress plus intermediate image previews | cfy advantage |
| Subgraphs | Versioned Creative Capsules with public ports, constraints and exposed parameters | Reusable subgraphs from templates and custom-node packs | Mooncast has richer lifecycle semantics; cfy has better creation and discovery |
| Templates | Two built-in capsules plus promoted and published user capsules | 89 checked-in blueprints, custom-node examples and a larger workflow ecosystem | Major cfy advantage |
| App Mode | Simplified recipe view with one brief field or a selected-video summary | Complex workflows can be exposed as focused applications | Mooncast implementation is currently minimal |
| Workflow portability | Immutable graph revisions and capsule versions | User-facing JSON save/load and workflow/seed recovery from supported generated media | cfy leads in everyday portability |
| Asset discovery | Query, kind/tag filtering, pagination, comparison, branching and promotion | Bulk scanning, metadata extraction, preview handling, tag facets and detailed browsing | cfy leads in discovery |
| Asset lifecycle | Immutable versions, parents, graph/run/node linkage, provider receipt, rights, QC, cost and annotations | Workflow metadata and seeds can be embedded in supported generated media | Mooncast leads in governed lifecycle; cfy has a better reopen-from-output experience |
| Human review | Named human gates, decisions, comments, evidence and review lenses | Usually modeled manually inside workflows | Major Mooncast advantage |
| Collaboration | Presence, comments, proposals, sharing, fork and compare | Primarily an individual workflow engine in core | Mooncast advantage |
| Agent architecture | Review-gated MoonClaw proposals with exact-base application; agents cannot satisfy human gates | No equivalent governed core collaborator | Mooncast advantage |
| Agent capability depth | Current proposals cover layout, mute, bypass and basic repair diagnosis | Not applicable | Mooncast has the right boundary but a shallow creative feature set |
| Production planning | Needs, strategy, creative development, asset factory, storyboards, routing, shots and control tower | Not a core concern | Major Mooncast advantage |
| Delivery lifecycle | Master promotion, packages, client decisions, portals, evidence and delivery milestones | Output-file nodes | Major Mooncast advantage |
| Commercial lifecycle | Leads, quotes, capacity, billing, economics and repeat orders | Not a core concern | Major Mooncast advantage |
| API embedding | Typed project, graph, run, editor, review and delivery APIs | Workflow execution API and App Mode | Both are strong for different consumers |

## Mooncast capabilities that should become graph operations

Mooncast already has useful creative behavior in its editor, but that behavior
is not generally composable from the workspace graph. The editor supports:

- frame-accurate move and trim;
- split and ripple editing;
- multi-selection and snapping;
- cross-dissolve, fade and wipe transitions;
- brightness, contrast, saturation and gamma;
- scale, position, rotation and opacity;
- text overlays and subtitle layers;
- rectangle and ellipse masks with feathering;
- bounded speed ramps;
- keyframes with hold, linear and ease-in/out interpolation;
- voice, music and SFX layers;
- audio volume, pan and mute;
- preview and export; and
- reviewed master promotion.

These existing features should be available as reusable operations or capsules:

- Trim video
- Crop and resize video
- Adjust image or video color
- Add an overlay
- Add captions
- Composite layers
- Apply a transition
- Mix or normalize audio
- Assemble a timeline
- Render a preview
- Export a master

This would grow the workspace substantially without introducing a second media
implementation.

## Missing feature families

### Creative-generation nodes

Mooncast needs directly usable, provider-aware operations for:

- text and structured-script generation;
- text-to-image and image-to-image;
- background removal, masks and compositing;
- product-image and character consistency;
- text-to-video and image-to-video;
- frame interpolation and upscaling;
- text-to-speech and voice cloning;
- speech-to-text;
- music and sound-effect generation;
- translation, subtitle generation and dubbing; and
- lip-sync or presenter/avatar video.

Provider routing should make the available model, expected price, expected
duration, permitted data class and representative outputs visible when the
user configures one of these nodes.

### Schema-generated controls

`NodeDefinition` describes ports, authority and ownership but does not include
a complete parameter-definition collection. The UI therefore falls back to a
generic parameter key/value/type editor.

Mooncast needs declarative parameters for:

- prompts and multiline text;
- integer and decimal ranges;
- sliders;
- enums and searchable choices;
- seed controls;
- provider and model selectors;
- asset selectors;
- resolution, aspect ratio and duration;
- color and curve inputs;
- repeatable values;
- optional and advanced fields; and
- defaults, examples and tooltips.

This is the highest-leverage enabling feature because it turns catalog entries
into usable creative tools and lets App Mode render those tools automatically.

### Outcome and template library

The existing outcome labels should become a curated, searchable gallery of
run-ready templates. Initial templates should include:

- Product images to social advertisement
- Brief to 30-second launch film
- Script to storyboard contact sheet
- Storyboard to animatic
- Long video to short highlights
- Podcast to captioned clips
- Existing campaign to localized variants
- Product demo to multilingual voiceover
- Approved shots to finished episode
- Master to reviewed delivery package

Each template should include a thumbnail or short preview, sample inputs and
outputs, exposed parameters, provider compatibility, estimated price and time,
and required human decisions.

### App Mode 2

The current App Mode handles either one brief textarea or a count of selected
videos. A complete App Mode should render a capsule's full public contract:

- typed files and reusable assets;
- repeatable inputs;
- exposed parameters;
- reviewed presets;
- provider/model choices;
- an estimate before execution;
- validation and blocking requirements;
- live run progress;
- intermediate previews;
- variant comparison and selection; and
- final output, editor and handoff actions.

This is the feature that makes sophisticated graphs useful to producers,
operators and clients who do not want to edit nodes.

### Agentic creative iteration

The current assistant can inspect validation/run failures and propose layout,
mute, bypass or repair changes. It should grow into a complete creative loop:

```text
Outcome request
  -> inspect assets and available capabilities
  -> propose a graph and explain the choices
  -> estimate providers, time and cost
  -> request the exact required approval
  -> run permitted nodes
  -> present intermediate outputs and variants
  -> compare and recommend
  -> apply the human selection
  -> open the specialized editor when needed
  -> prepare a reviewed delivery
```

The agent should also be able to promote a successful run into a capsule,
substitute an unavailable provider, and propose prompt or parameter changes
after a quality-control failure.

### Content-forward graph feedback

The graph should show the creative material being produced, not only execution
metadata. Depending on the artifact type, a node should be able to display:

- an image thumbnail or contact sheet;
- a video still or short preview;
- an audio waveform and playable preview;
- a script excerpt;
- a storyboard strip;
- a before/after comparison;
- variant candidates and the promoted selection; and
- a clear visual indication of which upstream change made an output dirty.

Node progress, preview and result presentation should use the same artifact
model as the asset library rather than introduce a separate preview-only type.

### Asset workbench

Mooncast should extend its governed asset model with creator-facing discovery:

- collections and boards;
- contact-sheet and waveform views;
- rich metadata facets;
- saved searches;
- variant-family and lineage visualization;
- side-by-side comparison with comments;
- bulk intake and classification;
- reuse and production-status indicators; and
- an `Open source workflow` action that restores the exact graph/capsule,
  inputs and parameters responsible for an artifact.

### Graph and editor round-trip

Generated graph outputs should open directly in the cut editor. Edits should
return to the graph as immutable timeline or master artifacts with parent
lineage. A successful edit sequence should be promotable to a reusable capsule.

The desired loop is:

```text
Generate variants
  -> select an asset
  -> open in timeline
  -> trim, composite, caption and mix
  -> render reviewed preview
  -> return a versioned timeline/master artifact to the graph
  -> continue review and delivery
```

## Recommended two-level graph

Mooncast should separate production intent from creative-compute detail.

```text
Production graph
Brief -> Creative approval -> Generate campaign -> Edit -> Client review -> Deliver
                                |
                                v
Creative-compute capsule
Model -> Prompt -> Generate variants -> Upscale -> Composite -> Select
```

The production graph remains understandable to producers and preserves
Mooncast's lifecycle. A Creative Capsule contains the lower-level generation
and transformation graph. Users may open the capsule when they need detailed
control; App Mode can expose only its public inputs and parameters.

This avoids both undesirable extremes:

- a production graph where generation is an opaque external box; and
- a canvas where hundreds of low-level model nodes are mixed with contracts,
  billing and client-delivery gates.

## Recommended feature order

### Phase 1: usable creative nodes

1. Add first-class parameter schemas and generated controls.
2. Define an executable binding for each creative node.
3. Expose existing media/editor operations as graph nodes or capsules.
4. Add the essential text, image, video, voice and music generation nodes.
5. Display intermediate creative previews and variant selections on nodes.

### Phase 2: outcomes rather than graphs

6. Build a curated template and outcome gallery.
7. Upgrade App Mode to render full capsule contracts.
8. Complete graph-to-editor and editor-to-graph round-tripping.
9. Add asset collections, lineage visualization and workflow reopening.

### Phase 3: agentic creative production

10. Let MoonClaw construct and explain graphs from outcome requests.
11. Let it run permitted operations and present variants for human selection.
12. Let it diagnose creative failures and propose prompt, provider or parameter
    changes.
13. Let it convert successful work into reusable, versioned capsules.

Advanced model experimentation, training and 3D should come later and only
where they materially support Mooncast's branded-video and episode-production
jobs.

## Product direction

The feature goal is not raw cfy parity. Mooncast should borrow cfy's creative
composability, parameter richness, preview loop, provider breadth and template
ecosystem while retaining Mooncast's own advantages:

- project and commercial intent;
- rights and provider policy;
- asset provenance;
- named human decisions;
- real video editing;
- client review;
- delivery evidence; and
- production economics.

The resulting product should feel like a creative workspace capable of making
content—not merely a governed project tracker and not merely a model graph.

## Primary implementation references

- `pack.json` — current governed tool and schema catalogue.
- `workspace/types.mbt` — graph, node, run, artifact and capsule contracts.
- `workspace/catalog.mbt` — manifest projection and bounded built-in nodes.
- `studio_service/workspace_execution.mbt` — current native execution coverage.
- `studio_service/workspace_agent_assistant.mbt` — current assistant depth.
- `ui/rabbita-mooncast/editor/workspace_view.mbt` — graph, App Mode, assets,
  inspector, assistant and run surfaces.
- `ui/rabbita-mooncast/editor/view_timeline.mbt` — timeline authoring features.
- `ui/rabbita-mooncast/editor/view_inspector.mbt` — effects, masks,
  transitions, curves and audio controls.
- `ui/rabbita-mooncast/studio/model.mbt` — ten-area production workspace.
- `../cfy/README.md` — cfy's declared creator-facing feature set.
- `../cfy/comfy_api/latest/_io.py` — rich node input/output definitions.
- `../cfy/execution.py` — graph execution, cache and node-output behavior.
- `../cfy/comfy_execution/progress.py` — live progress and previews.
- `../cfy/app/subgraph_manager.py` — subgraph and blueprint discovery.
- `../cfy/app/assets/` — asset discovery and metadata features.

