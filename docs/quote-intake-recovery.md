# Resuming an interrupted quoted intake

In Commercial intake, open **Draft initialization**. A pending initialization
offers **Resume draft initialization**. It uses that saved intention's original
quote version, quote digest and capacity digest, even if the selected quote or
current capacity board has changed. **Refresh initialization status** rereads
durable state. A failure can mean some initial work was saved; refresh and resume
the same row rather than creating a new quote or project.

## Durable protocol

Before committing a new conversion, the host saves a versioned local plan with
the exact conversion, graph, metadata, qualification, seven ordered draft
records, and original timestamp. The plan is visible even when interruption
precedes the commercial conversion. Project creation stores its initialization
digest atomically in the canonical project record. Unrelated same-ID work
cannot be adopted by a pending plan, even when its graph happens to match.

The conversion and each initial record are reconciled before their completion
checkpoint is written. A restarted request fills only missing, unacknowledged
steps. A present exact original artifact is reused; later versions, current
metadata and graph edits are retained. Missing downstream initial drafts keep
the frozen original dependency digests. They remain drafts and require the
ordinary creative/rights review. No approval, gate, payment or publication
authority is added by resuming.

Changed bytes under an initial artifact identity, removed acknowledged records,
tombstones and conflicting quote/project/capacity bindings return an explicit
conflict. Recovery never overwrites them or claims completion. The final
canonical projection is synchronized before the plan becomes complete, repairing
an interrupted canonical-to-production projection write.

Completed plans are terminal. Later intentional edits or removals are not
reseeded. Historical conversions with an existing project and no saved plan
are shown as legacy and remain readback-only. A new conversion can still join
an already existing exactly matching draft, preserving that draft's existing
metadata and creative history; it does not infer missing legacy seed work.
That terminal state is labeled **existing draft preserved**, rather than claiming
that missing legacy drafts were initialized.

## Concurrency and scope

Quote initialization and ordinary canonical project creation share a per-root
semaphore and an advisory OS lock. Root aliases are normalized before selecting
the semaphore. Another process receives a retryable in-progress response; the
OS releases its lock when the process exits. Project edits continue to use the
existing project mutation semaphore. This is a bounded intake recovery
protocol, not a general multi-writer transaction layer for all Studio services.

Optional initialization metadata is backwards-compatible with persisted
project records lacking the field. G0–G7, rights checks, caption resolution,
immutable archives and client acceptance are unchanged.

Regression fixtures use only synthetic local stores: interruption after each
plan/effect/checkpoint, process restart, concurrent attempts, edited partial
records, identity conflicts, legacy readback, and a real failed projection
write. Native HTTP dispatch and UI reducer/SSR evidence do not establish a
mounted browser, real provider, paid commission or deployed recipient flow.
