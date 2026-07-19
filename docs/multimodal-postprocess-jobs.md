# Multimodal post-processing jobs

Mooncast treats lip-sync, translation, and upscale as executable pack-local jobs,
not prompt annotations. Each versioned task binds exact immutable source assets,
rights, prompt, shots, provider/model, permitted data class, budget, and retry
policy. The provider-execution application supplies explicit named authority,
idempotent retry/resume, durable receipts, and immutable artifacts.

Completed outputs can be imported into a current shot, Cut Editor project, or
delivery build. Editor imports copy the exact provider bytes into the editor media
registry and retain the post-processing provenance digest. Import and execution
grant no publication authority.

The deterministic adapter remains validation-only. Commercial runs require a
configured adapter whose declared capability, provider, model, data class, and
commercial-use policy match the recorded task.
