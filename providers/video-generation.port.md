# Video generation provider port

Produces one bounded shot variant at a time. Requests include shot duration,
approved immutable references, negative constraints, provider/model version,
cost ceiling, retry policy, and fallback. Responses include attempt identity,
seed where available, media probe, output hash, cost, labels, and failure class.
