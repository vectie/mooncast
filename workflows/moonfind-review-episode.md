# MoonFind systematic review-episode expansion

This is the portable MoonFind/MoonFlow expansion for a 3–8 minute review
episode. Every node is an existing Mooncast manifest tool and uses its exact
versioned schema, authority, and idempotence. MoonFind may synthesize the graph;
MoonFlow may schedule it; only Mooncast executes Mooncast stages.

## Ordered graph

1. Create the 180-second production project from the exact creative brief.
2. Revise and independently decide the brief, rights ledger, IP bible, script,
   claims ledger, and storyboard. Advance only the gate supported by those
   decisions.
3. Record the reusable-asset plan. A named human approves the exact plan and a
   separate provider grant permits generation. Record five-dimension QC,
   approve immutable asset versions, and bind them to shots.
4. Record, render, and approve the duration-accurate animatic. Rendering needs
   an explicit process grant.
5. Record the model-routing plan. Invoke the decision operation separately for
   a named producer and named finance reviewer. Create the routed execution
   only after both approvals.
6. Execute pending shots with provider authority. Confirm the exact batch
   outputs across technical, continuity, safety, claims, and rights QC.
7. Import the G4-approved canonical production into the editor. Apply one or
   more revisioned cut commands. Freeze the current render plan and create the
   review preview.
8. Create the production export job from that exact plan. The native editor
   performs the real cut/render and verifies duration, streams, audio,
   subtitles, visible AI label, and provenance. Materialize the separate
   production-export envelope.
9. Promote the verified export as master. Invoke production review separately
   for technical-QC, creative-director, and rights/compliance reviewers.
10. Prepare the versioned delivery package. Plan and execute the customer
    delivery build, including deterministic variants, cuts, metadata,
    provenance/rights manifest, checksums, and immutable ZIP. A named human
    accepts the exact build digest.
11. Create the expiring client portal and record the exact client decision.
    Client acceptance supplies the client master decision and delivery
    milestone acceptance; it does not authorize publication.
12. Record final-deliverable evidence only after the accepted immutable build
    and client decision are available.

## Data dependencies

Each node consumes the immediately preceding typed artifact except for:

- creative decisions, routing decisions, production reviews, build acceptance,
  and client decision, which also require named-human transport bindings;
- provider/process stages, which require a separate expiring host authority
  artifact;
- editor cuts, which may repeat and form a revision chain;
- asset QC and production review, which fan out by required dimension/role and
  must all converge before the next gate.

The operation declaration is
`integration/moonflow/adapter-declaration.v1.json`. Health discovery must use
the live exercised-only attestation. An unexercised operation is not eligible
for unattended scheduling.

## Explicit exclusions

This graph does not publish, pay, email, or grant provider credentials. A
licensed real provider is required for commercial generated footage. The
deterministic ffmpeg fixtures establish replay and editor/render correctness
only.
