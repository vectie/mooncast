# Audition an audio track without changing the mix

Open a project in the Editor lens, choose the Program monitor's Interactive proxy,
and play an existing timeline with voice, music, or SFX. The Audio audition panel
lists actual audio tracks. Select **Solo voice**, then **Solo music** to compare
them while the playhead continues. Select the active solo again or **Restore full
mix** to restore ordinary monitoring.

This changes the actual program media elements' mute state, both when they mount
and immediately during playback. Their existing track gain, master volume,
persisted track mute, source position, and transport state remain intact. A
persistently muted track remains silent even when soloed and is labeled accordingly.
Video-track audio stays muted, matching the existing proxy compositor.

Solo is session-local monitor state, not an editorial command: it neither saves a
track mix nor changes history, a rendered preview, or an export. Changing project,
removing the soloed track, or switching program surfaces restores the full mix.
The rendered-preview surface disables audition controls. Busy/loading and
cross-project state reject new solo requests; Restore full mix remains available.

## Implementation and checks

The actual Editor `Msg`/`update` route updates the monitor state and calls the
existing `sync_program_media`. That function and `program_media_node` share the
same mute predicate. Full UI typechecking plus all Editor and shared package tests
run with `bash ../run-focused.sh [source-root]` from this round's source directory.
The focused tests use a deterministic HTMLMediaElement DOM adapter to assert
real mute/volume writes through the production update and synchronization path.
They cover switching, cancelling, master/track mute, gain, stale project guards,
removed tracks, project revisits, surface changes, and rendered controls.

Real-browser audible playback, native host HTTP integration, and exported-media
inspection remain unrun; a DOM adapter is not browser or acoustic qualification.
The pre-existing proxy's approximate dB-to-gain mapping is unchanged.

During scope research, `studio_service/editor_legacy.mbt` was found to ignore
legacy overlay text in `compatible_clip_payload`. This feature does not fix or
claim an end-to-end caption-correction workflow.
