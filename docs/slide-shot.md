# Slide a shot between its neighbors

In the Editor lens, select one middle video or audio clip. Enter a signed whole
number in **Slide frames**: positive moves the shot later; negative moves it
earlier. The preview names both affected neighbors and shows the proposed shot
start/end in timeline ticks. Choose **Slide shot** to apply all three changes as
one edit. Undo restores the three clips together.

The selected shot keeps its exact source in/out, duration, media reference and
identity. The left neighbor's out-point and the right neighbor's in-point move
by the same amount, leaving the three clips contiguous. Their outer boundaries,
later clips and other tracks stay unchanged. The Ripple toggle is ignored.
Unlike slipping a source window, this moves the shot's occupied timeline interval.

This operates on one track only. It does not maintain synchronization with
separate audio/video clips or linked groups on other tracks. Inspect those tracks
before choosing a slide. One output frame is rounded to the nearest timeline
tick, then multiplied by the entered offset; at 1000 ticks/s and 30000/1001 fps,
three frames means 99 ticks. This is not subframe-exact editing.

The selected clip must have exactly one adjacent neighbor on each side. All
three need unique nonblank IDs, valid source metadata, nonempty constant-speed
source windows and sufficient source handles. Conflicting metadata never
increases available handles. A gap, overlap, ambiguous ID, exhausted handle or
integer overflow blocks the action. Transitions touching any of the three,
keyframes, effects and legacy transition/effect/color/overlay settings must be
resolved separately. Static canonical settings are retained.

One existing revision-bound `group_trim` command contains all three trims and
travels through `/api/editor/projects/:project/commands`. The displayed cut is
not rewritten optimistically. The canonical response and existing history own
the result, Undo and Redo. Busy/loading, wrong-project and malformed frame-input
states cannot submit. A repeated click while pending cannot submit again; a
stale revision is rejected rather than applied to a changed cut.

The round's GUIDE describes focused fresh JS planner, actual Editor model/view
and native domain tests, including the exact planner JSON-to-native journey.
Static HTML rendering is tested, but no browser interaction, real-media playback,
full studio host build, installed lifecycle or release qualification is claimed.
No provider, rights, publication, client acceptance or payment authority changes.
