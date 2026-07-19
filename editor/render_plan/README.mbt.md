# Mooncast frozen render plan

This package projects one immutable editor revision into a renderer-neutral plan.
It binds clips either to approved generated-artifact evidence or rights-cleared
local intake receipts, freezes transition edit points, carries effect/audio
policy, produces readiness findings, and always sets `publication_authority` to
false.

`cache_projection` selects only clips intersecting a requested segment and hashes
their media, effect, transition, audio, output, quality, and revision inputs. A
renderer may cache that segment, but cannot change the key or infer authority.

The package performs deterministic computation only. Media probing, proxy
creation, cache storage/eviction, FFmpeg execution, and publication are separate
native-host/service responsibilities.
