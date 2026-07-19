# Editor HTTP application boundary

`routes()` is declarative. It does not register itself in Mooncast's global
router. Each handler accepts typed values and existing editor services and
returns a typed contract. Mutating handlers delegate to durable workspace/job
operations with explicit idempotency and revision anchors.

The host bridge still owns URL parsing, authentication, request-size limits,
JSON decoding, byte streaming, clock/ID creation, and error-to-status mapping.
Those concerns must not be reintroduced into the editor reducer.
