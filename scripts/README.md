# Repository commands

The legacy boundary script was removed after the native cutover. CI,
installation, validation, and runtime commands do not load scripts from this
directory.

The active fail-closed implementation is the MoonBit-native command:

```bash
moon run cmd/pack_boundary
```

The source-cutover record is retained under `migrations/`.
