# Semantic QC provider port

Analyzes one exact rights-cleared shot output for flicker, lip-sync quality,
character identity, or cross-shot continuity. Requests bind the shot attempt,
reference assets, neighboring-shot evidence, provider/model, data class, cost,
and retry limits. Responses use `mooncast.qc-semantic-result.v1` with a numeric
score, threshold, pass/fail observation, and note.

Provider output is evidence only. It creates no human decision and cannot open
G4 or authorize publication.
