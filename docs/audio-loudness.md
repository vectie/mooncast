# Make a measured loudness edition

An editor can compare an unusually quiet mix with a balanced listening copy
without altering the original. cmd/audio_loudness analyzes the explicitly
selected soundtrack, makes a two-pass loudness-normalized WAV, and measures the
actual output again before writing its completion receipt. It uses the existing
local FFmpeg/FFprobe tools; it does not call a generation provider.

This adds audio editing/output to the local media workflow. Existing audio
edition exports do not normalize loudness; alternate-soundtrack import accepts
an already synchronized mix. The new WAV can be inspected and then imported
through that existing path. It is an adjunct to the accessible-delivery journey,
not complete PRD MC-W07 or MOONCAST-R02 qualification.

## Inspect, measure, export, compare

Build cmd/audio_loudness and cmd/audio_media with the pinned toolchain,
private HOME/XDG and an absolute external target as described in the round guide.
Then use the resulting executable paths:

    LOUDNESS=/absolute/external/build/native/debug/build/cmd/audio_loudness/audio_loudness.exe
    ATTACH=/absolute/external/build/native/debug/build/cmd/audio_media/audio_media.exe
    "$LOUDNESS" inspect 'finished episode.mp4'
    "$LOUDNESS" measure 'finished episode.mp4' 2 -19 -2
    "$LOUDNESS" export 'finished episode.mp4' 2 -19 -2 'Balanced mix'
    "$ATTACH" preview 'finished episode.mp4' 'Balanced mix/normalized.wav' 0 fra 'Balanced mix'
    "$ATTACH" attach 'finished episode.mp4' 'Balanced mix/normalized.wav' 0 fra 'Balanced mix' 'Comparison edition'

Use the absolute stream index from inspect. With video at 0 and two audio
tracks at 1 and 2, 2 chooses the second audio track. There is no auto-selected
default. For a plain WAV, the audio index is normally 0.

measure scans the complete selected soundtrack and prints its integrated
loudness (LUFS), true peak (dBTP), loudness range (LU), source hash, target and
omitted streams. It makes no output files. Inspecting metadata alone is not a
loudness measurement. The example -19 -2 is an explicit editing choice, not a
platform delivery standard. Choose the target required by your brief.

export requires a fresh output folder whose parent exists. It always measures
the current input again; a stale saved measurement cannot determine an export.
Whole-number targets are bounded to -23 through -14 LUFS and ceilings to -3
through -1 dBTP. Mono remains mono and stereo remains stereo.

The source is never overwritten. The WAV can be reopened by inspect/measure,
or imported into an editor as a separate mix. The attach example makes a new
selectable track while preserving existing compressed picture, audio, captions
and chapters. It does not replace the existing default track. Choose the
balanced track in a player to compare. The MP4 path encodes the WAV to AAC, so
its measured true peak can differ; measure that derivative separately and do
not carry the WAV's numeric verification over to a lossy final master.

## Output and audible changes

The new folder contains:

- normalized.wav: one 48 kHz, 24-bit signed PCM track with original channel count
- before.json: exact input path/hash, selected stream, target and first measurement
- measure-before.log, encode.log, measure-after.log: FFmpeg diagnostics
- after.json: a new measurement of the actual emitted WAV
- result.json: written last, including output hash, complete probe, measured
  values, actual encoding mode and exact command arguments

The second pass requests linear gain, using the first pass's measured integrated
loudness, true peak, range, threshold and offset. FFmpeg can fall back to dynamic
normalization to satisfy peak/range constraints. The requested loudness-range
target is 11 LU; it is not a promise of an exact final range. The top-level
result.json.normalization_type records the encoding pass's actual mode.
Measurements also include normalization_type from the reporting analysis pass;
that field describes the analyzer's hypothetical output, not the WAV's history.

Linear gain changes level; dynamic processing can also alter dynamics. Resampling
to 48 kHz can occur. A 24-bit output does not recover precision or quality lost
from a source. The command adds no trimming, silence removal, speed change,
channel mixing, voice generation, denoising or stereo duplication. dual_mono
is false, so a mono track is measured as mono without stereo-playback compensation.

Output verification requires measured integrated loudness within 0.5 LU of the
chosen target and true peak no more than 0.1 dB above the chosen ceiling. This
small tolerance covers measurement rounding; it does not claim broadcast or
streaming compliance. The output must have the planned channel count, codec,
sample rate, one audio stream and duration within 50 ms of the input container.
That duration allowance covers codec/container tails, not intentional padding.
Listen to the result and review it against the brief before choosing a master.

## Scope, rejected inputs and recovery

- Local MP4/M4A, Matroska, WAV or FLAC files, 1 byte to 2 GiB, 3 seconds to
  2 hours. Inputs with no audio, unreadable content or unsupported containers fail
- Explicit zero-origin mono/stereo audio only; shifted audio and surround require
  a separate edit. No automatic alignment or downmix. Declared audio/container
  durations must agree within 50 ms; absent track duration is checked on the
  decoded output. A hidden shorter track can leave a rejected partial WAV
- Silence, non-finite measurements and integrated levels below -70 LUFS fail
  instead of inventing a successful normalized output. Difficult dynamic content
  may fail the post-export target check; choose a new folder after resolving it
- No video, captions, chapters, attachments or original container metadata in the
  WAV. Keep the full original alongside it. WAV does not carry the source's
  language/rights records; the receipt preserves the source track description
- Existing folders or dangling output symlinks are refused. FFmpeg uses -n;
  normal file writes are exclusive. Encoding/verification failure retains a
  partial folder and diagnostics. No result.json means the workflow did not finish
- Inputs are rehashed before completion. Use trusted, quiescent local folders;
  these checks are not a sandbox or a race-proof custody guarantee. Media command
  timeouts are 10 minutes each, and a long source may exceed available resources

This is a local derivative workflow. Rights clearance and approved use belong
to the studio's existing rights process. Numeric loudness, successful attachment,
internal completion and client acceptance are separate facts. The tool records
no rights approval, payment, recipient access or publication authority. Reports
contain local paths; review them before any separately authorized sharing.

## Focused evidence

scripts/verify_audio_loudness.mbtx ABSOLUTE_BUILD NEW_ABSOLUTE_EVIDENCE
NEW_ABSOLUTE_SAMPLES runs already-built commands and retains synthetic inputs,
derivatives, probes and logs. It covers mono/stereo, four audio containers and a
two-mix MP4, explicit second-track selection, actual output remeasurement,
decoded selected-tone frequency, full decode, source hashes, ordinary alternate
track attachment and unchanged original stream packets/chapters. It also
exercises silence, short/surround/damaged inputs, missing or non-audio selections,
out-of-range/fractional targets, hidden duration mismatch and occupied outputs.

Focused unit/doc tests cover selection, target bounds, measurement parsing,
numeric tolerances, output structure and exact process compilation. They do not
qualify speech intelligibility, mixed-program dynamics, accessibility, listening
quality, real-browser/device playback, rights, external client review, providers,
or a full release. Required strict-warning and broader gates remain blocking.
