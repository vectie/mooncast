# Mooncast Producer on MoonClaw

Mooncast supplies production policy, state, HTTP actions, and receipts. MoonClaw
supplies the `gpt-5.6-sol` agent runtime, model calls, job lifecycle, sessions,
memory, planning, and tool execution. No agent loop or generic job runtime lives
in the Mooncast pack.

## Pack-owned integration files

- `moonclaw.jobs.json`: the `mooncast-producer` four-stage job profile;
- `skills/mooncast-producer/SKILL.md`: operating and authority rules;
- `integrations/moonclaw/mooncast-producer.tools.json`: the exact HTTP-tool
  allowlist;
- `cmd/mooncast_producer_tool`: the native MoonBit HTTP adapter;
- `integrations/moonclaw/moonclaw.json`: optional workspace config template;
- `integrations/moonclaw/mooncast-producer.json`: integration ownership and
  model manifest.

The profile requests MoonClaw's canonical selector `codex/gpt-5.6-sol`, which
resolves the required `gpt-5.6-sol` model. The adapter exposes production,
editor, and delivery stages, but intentionally exposes no publication or
payment endpoint. It is not registered as a custom MoonClaw tool: each enabled
`job.analysis` step uses MoonClaw's existing generic shell execution tool to
run the pack-owned native command from the Mooncast workspace.

## Run it

Start the native Mooncast Studio from the Mooncast repository:

```bash
moon run cmd/studio
```

Install or merge the model template into the MoonSuite home used by MoonClaw
only when that home does not already select the exact model:

```bash
mkdir -p "$MOONSUITE_HOME/.moonsuite/products/moonclaw"
cp integrations/moonclaw/moonclaw.json "$MOONSUITE_HOME/.moonsuite/products/moonclaw/moonclaw.json"
```

Do not overwrite a configured file containing channel, credential, or provider
settings; merge only `agents.defaults.model.primary` in that case. The job
profile also pins every Producer step to the same selector.

Start MoonClaw with Mooncast as the job workspace:

```bash
cd /Users/kq/Workspace/moonclaw
moon run cmd/main -- gateway start --home "$MOONSUITE_HOME" --cwd /Users/kq/Workspace/mooncast
```

From a connected MoonClaw channel, create and confirm a job:

```text
/plan-job Mooncast producer: inspect project PROJECT_ID, run the explicitly authorized pending production stage, then prepare the editor handoff and report exact receipts.
/confirm PROPOSAL_ID
```

The request must include any named-human confirmation and exact authority that
the intended Mooncast action requires. `/confirm` authorizes the MoonClaw job;
it does not impersonate a Mooncast producer, finance reviewer, QC reviewer,
creative director, rights reviewer, client, or publisher.

For direct adapter diagnosis:

```bash
moon run cmd/mooncast_producer_tool -- health
moon run cmd/mooncast_producer_tool -- project.get PROJECT_ID
```

Set `MOONCAST_STUDIO_URL` when Studio is not on its default loopback port. The
native adapter rejects non-loopback hosts and bounds the JSON request body to
1 MiB, the JSON response to 8 MiB, and each action to ten minutes.

## Stage boundary

The Producer can inspect and call the systematic production stages already
implemented by Mooncast. Its preferred high-level actions are:

1. create or inspect an exact routed execution after G3;
2. use the deterministic Production coordinator to run all pending routed jobs;
3. use the coordinator to record a complete explicitly confirmed QC batch;
4. import the exact G4 production into the cut editor;
5. start or inspect an authorized editor export;
6. create and run a delivery build after the required master and gate receipts.

Creative approvals, rights clearance, finance approval, QC confirmation,
editorial taste, master promotion, delivery acceptance, publication, payment,
and Bookkeeper/MoonFlow adoption remain explicit external decisions.
