---
name: mooncast-producer
description: Operate Mooncast's governed episode-production HTTP stages from a MoonClaw-owned agent runtime.
---

# Mooncast Producer

Use this skill only inside a MoonClaw job running against the Mooncast workspace.
MoonClaw owns the model call, agent loop, session, memory, planning, scheduling,
and tool runtime. Mooncast owns production facts, policies, assets, receipts,
and the HTTP actions exposed by its native Studio.

## Required operating method

1. Read `integrations/moonclaw/mooncast-producer.tools.json` before calling a
   stage tool.
2. Use MoonClaw's generic shell execution tool only to run the pack-owned native
   command as `moon run cmd/mooncast_producer_tool -- ...` from the Mooncast
   workspace. There is no custom MoonClaw tool registration. Do not construct
   arbitrary Mooncast URLs or invoke `curl`.
3. Inspect `project.get`, `project.governance`, and the relevant execution,
   editor, or delivery record immediately before every mutation.
4. Copy revision and digest bindings from the current HTTP response. Never
   infer, shorten, repair, or reuse a stale binding.
5. Use `production-coordinator.run-pending` for a complete authorized routed
   execution. Use `production-coordinator.confirm-qc` only when a named human
   has explicitly confirmed the complete current output/evidence set.
6. Treat proposal confirmation in MoonClaw as permission to run the job, not as
   a substitute for Mooncast's named-human creative, rights, finance, QC,
   client, delivery, publication, or performance decisions.
7. After G4, use `editor.production-import` to create or refresh the governed
   cut-editor workspace. The Producer can prepare the editor; it cannot make
   editorial taste decisions or promote a master without exact authority.
8. Never call publication or payment effects. This adapter intentionally
   exposes neither.
9. After any mutation, re-read the authoritative resource and report its exact
   revision, digest, receipts, costs, and remaining gate.

## Adapter invocation

```text
moon run cmd/mooncast_producer_tool -- <tool-id> [resource ids ...] [JSON body or @body-file]
```

Examples:

```text
moon run cmd/mooncast_producer_tool -- project.get project-123
moon run cmd/mooncast_producer_tool -- production-coordinator.run-pending project-123 execution-456 @request.json
moon run cmd/mooncast_producer_tool -- production-coordinator.confirm-qc project-123 @qc-request.json
moon run cmd/mooncast_producer_tool -- editor.production-import project-123 '{}'
```

The adapter reads `MOONCAST_STUDIO_URL`, defaulting to
`http://127.0.0.1:8765`. It accepts only loopback HTTP authorities. Request
bodies, responses, and request duration are bounded by the native command.

## Completion contract

Return observed facts, performed actions, immutable receipt identifiers,
remaining human decisions, and one recommended next action. A blocked gate is a
valid result. Never relabel a fixture render, queued job, pending QC result, or
authorization receipt as an accepted final episode.
