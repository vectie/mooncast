# MoonCast UI-to-UI qualification

This guide covers every published MoonCast application entrypoint and the
governed transitions between them. It is an operator procedure, not a claim
that the deterministic provider is commercial media quality.

## Published-entrypoint truth

| Manifest entrypoint | URL on the native host | Purpose |
| --- | --- | --- |
| `production-studio` | `/apps/mooncast/studio` | Internal project, evidence, gate, provider, delivery, and commercial control surface. |
| `cut-editor` | `/apps/mooncast/editor` | Governed timeline, local-media intake, preview, export, and master-promotion surface. |
| `client-review` | `/apps/mooncast/client/<token>` or `/client/<token>` | Least-authority customer review bound to one exact master and delivery build. The entrypoint without a token must deny access. |
| `campaign-studio` | `/apps/mooncast/studio` | Deprecated compatibility alias only; it executes the same Studio application and is not a fourth runtime. |

All three applications are served by one MoonBit native host and one Rabbita
release. MoonCast does not contain an agent runtime or a Bookkeeper UI.
MoonClaw owns agent execution; MoonFlow owns orchestration; accepted outcome
learning belongs to MoonBook's Bookkeeper.

## Prerequisites and launch

Verify the approved local media tools yourself; the application will not
download them:

```sh
command -v ffmpeg
command -v ffprobe
```

Build and run:

```sh
cd /Users/kq/Workspace/mooncast
npm --prefix ui/rabbita-mooncast install --no-audit --no-fund
npm --prefix ui/rabbita-mooncast run build
MOONCAST_RABBITA_DIST=ui/rabbita-mooncast/dist \
MOONCAST_DATA_ROOT=var/qualification-creative \
MOONCAST_PORT=4302 \
moon run cmd/studio
```

Readiness URLs:

- <http://127.0.0.1:4302/health>
- <http://127.0.0.1:4302/apps/mooncast/studio>
- <http://127.0.0.1:4302/apps/mooncast/editor>
- <http://127.0.0.1:4302/apps/mooncast/client>

Use a dedicated qualification data root so the exercise does not modify
accepted production evidence.

MC-2 through MC-4 need a production-backed editor project. To reproduce the
repository's deterministic 180-second qualification fixture once, run:

```sh
cd /Users/kq/Workspace/mooncast
moon test studio_service/episode_acceptance_wbtest.mbt \
  --target native \
  --filter '*governed 180 second episode*'
```

The test prints `mooncast acceptance root: ...` and `mooncast acceptance
master: ...`. Stop the earlier host and restart it with the printed root as
`MOONCAST_DATA_ROOT`; do not rerun this three-minute fixture after each UI
interaction. This fixture proves workflow and media plumbing only. A commercial
qualification still requires real provider output and named customer review.

## Use case MC-1: Studio creates a governed draft

Goal: prove that Studio creates a complete 3–8 minute project graph while
leaving approval and provider effects pending.

1. Open **Production Studio**.
2. In **Start a saleable episode**, enter:
   - Project ID: `creative-ui-qualification-001`
   - Title: `MoonSuite visual identity episode`
   - Payable objective: `Deliver a reviewable three-minute MoonSuite identity narrative`
   - Audience: `MoonSuite product teams`
   - Channels: `review-only`
   - Rights owner: `MoonSuite product owner`
   - Duration seconds: `180`
   - Maximum budget CNY: `20000`
3. Choose **Rights remain pending** once so it changes to
   **Rights owner confirmed**.
4. Choose **Create governed project**.
5. Confirm the project appears in the left project ledger.
6. Confirm the Overview shows a project/episode/scene/shot graph and seven
   version-one creative drafts.
7. Open **Creative**, **Asset Factory**, **Storyboard / Animatic**,
   **Routing**, **Shot board**, **Delivery**, and **Commercial**.
8. Confirm unapproved stages show prerequisites rather than fabricated
   completion.

Expected evidence:

- A durable production project and append-only project events exist below the
  selected `MOONCAST_DATA_ROOT`.
- G0–G7 are visible and no gate is silently passed.
- Provider execution, publication, and payment effects remain false.
- The campaign compatibility entrypoint opens this same Studio state.

### Governed negative

Set duration to `120` or budget to `0`, then choose **Create governed
project**. The UI must show:

`Project id/title, 180–480 seconds, and a positive budget are required.`

No project should be added.

### Recovery

Set duration to `180`, provide a positive budget, keep a unique safe project
ID, and submit again. A duplicate ID should be handled by choosing a new
qualification ID rather than deleting or overwriting the earlier record.

## Use case MC-2: edit a governed production

Prerequisite: select a project whose G4 shot evidence has been imported into
the editor. A blank editor catalog is an honest setup state, not a failed UI.

1. Open **Cut Editor**.
2. Choose the qualification project and **Open project**.
3. Inspect **Project tree** and **Takes & media**.
4. Select an eligible take and choose **Add at playhead**.
5. Move the playhead, select the clip, and use the Inspector to change one
   reversible property such as opacity.
6. Add a title and set one keyframe.
7. Toggle **Source** and **Program** monitoring.
8. Create an authoritative review preview.
9. After the preview succeeds, compare its immutable digest with the displayed
   render-plan state.
10. Create an export, wait for success, supply the named actor/authority
    reference, and promote the exact export to the canonical master.

Expected evidence:

- Timeline edits advance the canonical editor revision.
- Undo/redo operate through the command log.
- Interactive proxy remains labelled as non-authoritative.
- Approval preview/export binds to a frozen render plan and immutable output
  digest.
- Promotion does not publish and does not create client acceptance.

### Governed negative

Attempt to add a take whose QC or rights state is not eligible. The add action
must remain disabled or the command must be rejected. A stale editor revision
must reload canonical state rather than merging local edits.

### Recovery

Resolve the QC/rights evidence in its owning production stage, reload the exact
project revision, and repeat the edit. Do not change client or rights evidence
inside the editor merely to make a take eligible.

## Use case MC-3: rights-cleared local image/logo intake

This path exercises the corrected binary picker.

1. Open a production-backed editor project.
2. Expand **Rights-cleared local media intake**.
3. Choose role **logo**.
4. Choose a PNG, JPEG, or bounded VP8X WebP file.
5. Confirm the UI automatically fills safe name, MIME type, byte length, and
   `sha256:…` from the selected browser Blob.
6. Set duration, rights owner, rights basis, territory, channels, rights
   reference, source kind, and source reference.
7. Choose **Create intake and upload exact bytes**.
8. Confirm the new take appears selected in **Takes & media**.
9. Choose **Add at playhead** and inspect the logo on the Program monitor.

Expected evidence:

- The server verifies the exact Blob length, SHA-256, MIME signature, image
  bounds, production identity, rights record, and current editor revision.
- The local-media binding and intake receipt enter the frozen render plan.
- The browser does not substitute pasted text for selected binary media.
- A still image may show `duration pending` in source analysis because ffprobe
  does not report container duration. Its governed timeline duration comes
  from the intake request and add-clip template instead.

### Governed negative

Choose an SVG while role is `logo`, or deliberately alter a manually entered
digest. MoonCast intentionally rejects SVG and mismatched bytes.

### Recovery

Choose a compatible PNG/JPEG/WebP. Allow the browser to recompute its exact
digest; do not copy the old digest forward. Reconfirm the rights and source
reference, then submit.

## Use case MC-4: private client review

Prerequisites:

- a promoted canonical master;
- three internal master approvals;
- a versioned delivery package;
- a completed exact delivery build; and
- a named Studio operator with human confirmation.

1. In Studio, open **Delivery**.
2. Under **Expiring review portals**, enter the client name, brand name,
   accent, and a future ISO-8601 expiry.
3. Choose **Create one-time client URL**.
4. Copy the URL immediately; MoonCast stores only its token digest.
5. Choose **Open Client Review**.
6. Confirm the page shows the expected project title, exact master digest,
   build digest, duration, and **Publication: Not authorized here**.
7. Play or seek the bound master.
8. Add a named timecode annotation.
9. Choose **Request changes** and provide a note, or choose **Approve
   delivery**.
10. Confirm decision authority and choose **Record immutable decision**.
11. If approved, confirm the delivery-package download unlocks and an exact
    decision receipt appears.

Expected evidence:

- The annotation and decision bind to the exact master/build pair.
- A revision request consumes one of at most two contracted rounds.
- Client approval records delivery acceptance but cannot publish or process
  payment.
- Provider configuration, filesystem paths, raw tokens, and internal controls
  are absent from the client projection.

### Governed negative

Open `/apps/mooncast/client` without a token. The page must say the URL has no
portal token. Revoke or expire a valid portal in Studio and reload it; it must
show the corresponding closed state and offer no decision mutation.

### Recovery

Return to Studio, verify the current master/build binding, and create a new
future-dated portal. Never reactivate or reconstruct the old raw token.

## One proportional qualification pass

Run implementation validation once after all localized fixes:

```sh
cd /Users/kq/Workspace/mooncast
moon fmt
moon info
moon check --target native
moon test --target native
npm --prefix ui/rabbita-mooncast run build
```

Then perform MC-1 through MC-4 in one browser session. Avoid rerunning the full
180-second fixture after every UI change. The stricter repository-wide
`--deny-warn` release gate remains separate until the recorded legacy warning
backlog is cleared.

## What was actually tested

Qualification date: 2026-07-31.

- Manifest, native route, and visible-control truth were inspected for Studio,
  Cut Editor, Client Review, and the deprecated campaign alias.
- The cut editor's binary-selection defect was fixed: selected Blob bytes now
  supply the displayed name/type/size/digest and the later upload.
- The visible PNG replay exposed and fixed a still-image probe defect:
  ffprobe may omit `format.duration`; MoonCast now accepts that valid response,
  creates a thumbnail/proxy, and retains the intake-defined timeline duration.
- The visible add-to-timeline replay exposed and fixed a lossy Rabbita
  `ClipSettings` projection. Canonical flat clip settings now survive the
  browser command round trip. A focused golden test covers that contract.
- The same replay exposed a stale `already_placed` projection. The UI now
  derives placement from the canonical timeline and also refuses a duplicate
  add command for the same media reference.
- MC-3 visibly passed against the durable `acceptance-episode` fixture at
  editor revision `r3`: the exact MoonVis PNG take showed **Placed**,
  **Already placed** was disabled, exactly one logo clip remained on
  `track-ai-label` from `00:00` through `00:05`, and no error was visible.
- The Program monitor visibly rendered the base frame and MoonVis mark at
  `00:00`; the UI reported `16/16 sources bound`. Source routes served the
  original MIME-correct bytes instead of substituting a proxy under source
  metadata.
- Final visible evidence:
  `/Users/kq/Workspace/mooncast/_build/ui-to-ui/2026-07-31-consolidated/editor-logo-overlay-r3-final.png`.
- Focused validation passed: the clip-settings round-trip test, native Studio
  package check, and production Rabbita build. This result qualifies the
  exercised MC-3 and MoonVis-to-MoonCast path; it does not by itself claim
  that every action in MC-1, MC-2, or MC-4 was replayed.
