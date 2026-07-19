# Mooncast production book

Store briefs, source rights, prompts, raw generations, provenance, reviews,
delivery packages, and publication receipts as immutable production records.

Systematic productions additionally retain:

```text
projects/{project_id}.json
project-events/{project_id}.ndjson
assets/asset-{digest}.mp4
records/asset-{digest}.json
masters/master-{digest}.mp4
masters/master-{digest}.srt
master-provenance/master-{digest}.json
deliveries/{project_id}/delivery-{digest}.json
```

The project record contains its project → episode → scene → shot → asset graph,
rights ledger, bible, script, storyboard, animatic, model route, budget, reviews,
analytics, and economics. Events and content-addressed evidence make restart
recovery and acceptance audits independent of the UI process.
