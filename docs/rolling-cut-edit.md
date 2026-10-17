# Roll a cut without shifting episode timing

In the Editor lens, select two adjacent video or audio clips on one track
(using multi-select), then choose **Roll −1f** or **Roll +1f** under the timeline
toolbar. A later roll extends the first clip and removes the same amount from
the start of the second. An earlier roll does the reverse. The pair's outer
boundaries, all later clip positions, clip IDs and source asset lineage stay
unchanged. This action ignores the Ripple toggle deliberately.

One step uses the output frame rate, quantized to the nearest timeline tick
(default 24 fps when no output rate exists). The controls explain this rounding.
The source metadata must prove the needed handles. Unknown or conflicting
metadata cannot increase available handles. A roll cannot empty either clip.
Transitions touching either clip, effects/keyframes and speed-mapped clips are
held for manual editing rather than silently damaged.

Both trims travel as one existing revision-bound group_trim command through
/api/editor/projects/:project/commands. The UI waits for the canonical reply;
it never invents a successful timeline locally. Undo restores the pair as one
decision. Redo and replay use the existing immutable domain command history.
Loading, busy and wrong-project states cannot submit a roll. Rejected/stale
commands use the existing reconciliation path without altering the source cut.

## Verification

Run `bash /path/to/source/scripts/test-rolling-edit.sh [optional-source-root]`
from any working directory. The runner
uses the pinned process-only toolchain, private HOME/XDG, absolute external
build directories, the shared native lock and local copies of exact retained
dependency caches. A fresh checkout materializes these already-approved package
bytes before frozen builds; no downloads or version substitutions occur.
Override MOONCAST_ENVIRONMENT, MOONCAST_RABBITA_CACHE (0.12.4), MOONCAST_X_CACHE
(0.4.40) and MOONCAST_ROLL_WORKER for another authorized environment.

The runner checks the actual full UI module, tests the actual editor/shared
packages and executes the actual dependency-free domain package in a minimal
native test module. It does not substitute provider dependencies or claim a
full native host build. Browser interaction, actual media playback, provider
production and release qualification remain unverified.
