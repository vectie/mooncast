# Slip one source window

Select exactly one video or audio clip in the reconciled editor timeline. Use
**Slip −1f** for earlier source content or **Slip +1f** for later content. Each
click shifts both source endpoints equally by one signed output-frame step.
The clip's timeline start and duration, its references and neighboring clips
stay unchanged. The output frame duration is rounded to the nearest timeline
tick; repeated steps use this quantized duration (for example, 33 ticks at
1000 ticks/second and 30000/1001 fps). This is not subframe-exact media editing.

Source metadata must supply valid positive duration and enough source handles.
Conflicting take durations use the smaller limit. Empty or multiple selections,
unsupported tracks, duplicate/missing IDs, touching timeline transitions,
effects, keyframes, retimed duration mismatches, invalid timing and out-of-range
arithmetic block the action. A busy/loading or mismatched project also blocks it.

The control sends one existing canonical `trim` command with the current
workspace revision and idempotency key. It does not optimistically rewrite the
displayed timeline. The existing command response and history route supplies
Undo/Redo; stale revisions are rejected by the canonical native domain.

This bounded workflow does not introduce slip-drag tools, arbitrary numeric
entry, multi-clip slip, slide, retiming, effects/transition adaptation, media
playback qualification or new release-gate acceptance.
