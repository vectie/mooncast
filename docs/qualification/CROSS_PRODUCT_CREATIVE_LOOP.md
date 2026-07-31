# MoonVis → MoonCast creative loop

This is the currently honest creative cross-product path. MoonVis resolves and
visually inspects a reviewed brand asset; MoonCast freezes the exact compatible
bytes, rights evidence, edit decisions, rendered master, and client review.
The products do not import each other's source packages.

## What is connected

```text
MoonVis canonical catalog
  → reviewed video-channel bundle
  → transparent PNG + digest + license limitation
  → MoonCast governed local-media intake
  → logo take and timeline overlay
  → preview/export/master
  → exact-build client review
```

The handoff is an immutable artifact boundary. MoonFlow may later transport the
typed references and MoonClaw may execute an explicitly authorized plan, but
neither is required to pretend the two UIs share a runtime.

## Exact compatible asset

| Field | Value |
| --- | --- |
| MoonVis asset ID | `moonsuite.mark.video-overlay.transparent` |
| Asset catalog version | `1.1.0` |
| Repository path | `/Users/kq/Workspace/moonvis/src/imports/moonsuite-mark-transparent.png` |
| MIME type | `image/png` |
| Bytes | `38297` |
| SHA-256 | `sha256:34ff722b02b79c0950ba0e65f2412a859ca6bb2fccc1ae094f31b4cefe89190f` |
| Usage | `video-overlay` |
| Rights condition | MoonSuite project asset; distribution rights require product-owner confirmation |

MoonVis's SVG variants remain useful design sources but are not compatible with
MoonCast's intentionally bounded PNG/JPEG/WebP image intake.

## Prerequisites

Start MoonVis:

```sh
cd /Users/kq/Workspace/moonvis/ui/rabbita-moonvis
npm install
npm run dev
```

Start MoonCast in a second terminal:

```sh
cd /Users/kq/Workspace/mooncast
npm --prefix ui/rabbita-mooncast install --no-audit --no-fund
npm --prefix ui/rabbita-mooncast run build
MOONCAST_RABBITA_DIST=ui/rabbita-mooncast/dist \
MOONCAST_DATA_ROOT=var/qualification-creative \
MOONCAST_PORT=4302 \
moon run cmd/studio
```

URLs:

- MoonVis: <http://127.0.0.1:4198/>
- MoonCast Studio: <http://127.0.0.1:4302/apps/mooncast/studio>
- MoonCast Editor: <http://127.0.0.1:4302/apps/mooncast/editor>

A production-backed MoonCast editor project is required before media intake.

## UI-to-UI procedure

### 1. Resolve and inspect in MoonVis

1. In MoonVis, choose product **mooncast**.
2. Choose channel **video**.
3. Keep **current binding** selected.
4. Record the bundle digest, token version, and asset version.
5. Inspect `moonsuite.mark.video-overlay.transparent`.
6. Confirm the rendered image, path, MIME, byte length, and SHA-256 match the
   table above.
7. Obtain a named product-owner decision before external distribution.

### 2. Freeze the asset in MoonCast

1. In MoonCast Editor, open a production-backed project.
2. Expand **Rights-cleared local media intake**.
3. Select role **logo**.
4. Choose
   `/Users/kq/Workspace/moonvis/src/imports/moonsuite-mark-transparent.png`.
5. Confirm the automatically computed SHA-256 exactly matches MoonVis.
6. Enter:
   - Rights owner: the named product owner;
   - Rights basis: the reviewed distribution/production basis;
   - Territory and channels: the contracted delivery scope;
   - Rights reference: the durable decision/rights-ledger reference;
   - Source kind: `moonvis-bundle`;
   - Source reference:
     `moonvis://bundle/<bundle-digest>#asset=moonsuite.mark.video-overlay.transparent`.
7. Choose **Create intake and upload exact bytes**.
8. Confirm the take is registered with cleared rights and exact lineage.

### 3. Edit, render, and review

1. Choose the new logo take.
2. Move the playhead and choose **Add at playhead**.
3. Set position, scale, opacity, and any required keyframes in the Inspector.
4. Request an authoritative review preview.
5. Inspect the logo against actual moving pixels; MoonVis explicitly leaves
   this contrast check runtime-bound.
6. Export and promote only the frozen approved render plan.
7. In Studio Delivery, create a portal for the exact completed build.
8. In Client Review, play the master, add a timecode note about the logo, and
   approve or request revision.

## Expected evidence chain

The final chain should retain:

1. MoonVis bundle digest and catalog version;
2. MoonVis asset ID, digest, byte length, provenance, and license class;
3. MoonCast local-media intake request and receipt;
4. product/episode/scene/shot identity;
5. rights attestation and named rights reference;
6. editor command-log revision and logo clip settings/keyframes;
7. frozen render-plan digest;
8. preview/export/master SHA-256;
9. client annotation/decision bound to the exact master and build.

The source reference makes lineage reviewable, but MoonCast remains responsible
for its own rights, edit, QC, and acceptance policy.

## Governed negative and recovery

### Stale MoonVis binding

Choose **simulate stale consumer** in MoonVis. If **DRIFT** is visible, stop the
handoff. Recover by updating the consumer expectation and returning to
**current binding / ALIGNED**.

### Incompatible SVG

Select either MoonVis SVG in MoonCast while role is `logo`. MoonCast must reject
the MIME/format boundary. Recover by selecting the cataloged transparent PNG;
do not weaken the validator or rename SVG bytes to `.png`.

### Digest or byte mismatch

If MoonCast's browser-computed digest differs from the MoonVis card, stop. Check
that the exact canonical file—not a screenshot, resized export, or browser
download conversion—was selected. Re-resolve MoonVis and choose the exact bytes
again.

### Missing rights

Catalog provenance is not permission. If product-owner confirmation is absent,
keep the take out of accepted delivery. Recover by recording a named decision
and binding its reference in MoonCast.

## Why MoonMoon is not in this creative flow

MoonMoon currently emits lunar mission/route/simulation evidence for
MoonRobo/MoonFlow. It does not emit an accepted image, video, camera capture,
or creative-render manifest compatible with MoonCast. Its WebGL/canvas view is
an inspection surface, not an export contract.

Adding MoonMoon merely because it has attractive pixels would break evidence
truth. A future integration should begin with a MoonMoon-owned reviewed render
schema containing source model/version, camera, timestamp/lighting state,
resolution, color transform, rights/license, digest, and claim limitations.
Until then, MoonMoon remains outside this loop.

## What was actually tested

Qualification date: 2026-07-31.

- The source asset's actual bytes, length, MIME type, and SHA-256 were verified.
- MoonVis was changed to expose and render that compatible asset in its
  canonical video bundle.
- The coordinating browser run visibly passed MoonVis's current video binding,
  asset rendering, context adaptation, and stale-binding recovery.
- MoonCast was changed to hash and upload the selected browser Blob instead of
  uploading text-area content under binary metadata.
- The exact PNG was durably ingested; its follow-up analysis now handles the
  valid ffprobe still-image response with no container duration and produces a
  review thumbnail.
- The final visible MoonVis → MoonCast replay passed at editor revision `r3`.
  The take projected as **Placed**, its add control projected as disabled
  **Already placed**, and the durable timeline retained exactly one copy of
  the logo from `00:00` through `00:05`.
- The Program monitor visibly composited the base frame and canonical MoonVis
  mark at `00:00`, reported `16/16 sources bound`, and showed no error.
  Evidence:
  `/Users/kq/Workspace/mooncast/_build/ui-to-ui/2026-07-31-consolidated/editor-logo-overlay-r3-final.png`.
- This replay proves asset resolution, exact-byte intake, analysis, placement,
  idempotent UI projection, and interactive composition. It does not claim
  that an authoritative export, master promotion, or final client decision
  was performed during this focused pass.
