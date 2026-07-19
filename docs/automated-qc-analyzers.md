# Automated QC analyzers

Mooncast now executes ten first-class analyzers. Codec, duration, blank-frame,
audio-stream, subtitle-timing, and subtitle-safe-area checks run locally through
argv-only ffprobe/ffmpeg or exact subtitle layout receipts. Flicker, lip-sync
quality, identity, and continuity use explicit external semantic provider ports.

Every task binds the exact project revision, shot attempt/output digest, rights,
thresholds, references, provider/model where relevant, budget, and retry policy.
Runs persist immutable measurements, evidence, cost, network-effect receipts,
and one analyzer finding. Studio copies that finding into the existing Technical
or Continuity G4 evidence stream. It deliberately creates no `QcDecision`; a
named human must still approve or reject the exact current finding.
