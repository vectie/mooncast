# Shot-generation provider port

The port accepts an authorized `ShotRecord` and returns an immutable generation
attempt plus asset provenance. Capabilities declare modality, maximum duration,
model/version, commercial-use basis, estimated price, timeout, retry behavior,
and fallback eligibility. The checked-in deterministic adapter renders at most
12 seconds per unique shot and is suitable for fixtures and local review.
