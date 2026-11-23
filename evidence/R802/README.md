# R802 development evidence

Feature: whole-track caption synchronization in the offline screening player.
Source: October 20 restored MoonCast baseline, selected by CURRENT-SOURCES.json.
Work copy: `moonsuite-cloud-20261020/work/R802/mooncast`.

The product role is an editor assembling and inspecting a coherent master.
The current PRD's graph/editor journey and readable required captions, together
with PRODUCT_CONTRACT's subtitle editing ownership, ground this feature.
Existing screening-caption-correction documentation explicitly left bulk clock
synchronization to the CLI. This round connects that operation to listening in
the offline player, rather than introducing a new format or review gate.

## Verification

- `focused-tests.txt`: 44/44 focused Node tests of the production embedded JS,
  including five new feature tests and existing edit/timing/replace/resume.
- `native-screening-final.txt`: native screening package including the native
  clock-equivalence example and generated HTML control assertions.
- `info.txt`: actual targeted `moon info --frozen editor/screening` result.
- `fmt.txt`: actual package formatter result. Unrelated Int32 spelling changes
  in `plan.mbt` were reverted to the retained source; no behavior changed there.
- `dependency-update.txt`: official registry update, followed by successful
  resolution at unchanged declared versions. Retain `.mooncakes` inputs.
- `native-screening.txt`: initial failed native attempt, retained accurately.
- `native-screening-retry.txt`: recovered seven baseline tests before the new
  native equivalence test was added.

Native commands used the shared native-build lock, `--strip -j2`. No provider,
FFmpeg operation, Mac access, remote publication or deployment was performed.

## Concrete compiler compatibility

The current compiler removed `try?`. Twelve expressions in the selected existing
`editor/screening/plan_test.mbt` now use explicit `try Ok(...) catch { e => Err(e) }`
with the same success/error assertions. The initial failure is retained. The
generated `editor/screening/pkg.generated.mbti` changed only integer spelling
from Int to Int32 after actual `moon info`. No public behavior or manifest
dependency version was changed. Neighboring source `plan.mbt` remains identical
to the baseline.

## Limits

DOM, media track and download tests use the established doubles. Native tests
compile and execute the real HTML producer and existing caption clock primitive.
No real browser, media decoder, full studio build, real-provider production,
speech-alignment measurement, client acceptance or release qualification was
run. Downloaded captions require editorial listening. This is a source-level
feature handoff pending independent review, not release-ready product approval.

No cleanup was performed. Source, official dependency inputs and native build
outputs remain for parent-coordinated delivery and cleanup.
