# Show two caption languages together

`cmd/bilingual_captions` combines two existing caption drafts into a single
plain-text subtitle track. This is useful for a bilingual interview, language
learning video, or review copy where the viewer needs to see both versions at
once. The input cues do not need matching numbers or boundaries.

Text from the primary draft appears first, followed by a newline and any active
secondary text. The output splits at every start and end in either draft. A
translation that begins later therefore appears later; neither text is held
across its gaps. All intervals are half-open `[start_ms, end_ms)`. This is timed
composition of existing wording, not translation or automatic alignment.

## Preview, compose, edit, and embed

Use the pinned environment and exact dependencies documented in this round's
`BUILD.md`. With the native binaries built in an absolute external target:

```sh
TARGET=/absolute/external/mooncast-build
BILINGUAL="$TARGET/native/debug/build/cmd/bilingual_captions/bilingual_captions.exe"
EDIT="$TARGET/native/debug/build/cmd/caption_edit/caption_edit.exe"
"$EDIT" import English.srt 6000 english.json
"$EDIT" import Chinese.vtt 6000 chinese.json
"$BILINGUAL" preview english.json chinese.json
"$BILINGUAL" export english.json chinese.json 'Bilingual review'
"$EDIT" show 'Bilingual review/captions.json'
"$EDIT" set 'Bilingual review/captions.json' 1 500 1000 'Hello, garden!' corrected.json
"$EDIT" export corrected.json corrected
```

The example times and cue number are illustrative. Check `show` before editing.
For an immediate six-second example use `fixtures/bilingual-primary.json` and
`fixtures/bilingual-secondary.json` instead of importing your files. Their
two/three input cues produce seven display intervals, with 2500 ms of shared
coverage, 1000 ms primary-only, 1000 ms secondary-only, and 1500 ms uncaptioned.

To reverse the text order, swap the two input arguments and choose a new output
folder. Existing line breaks, punctuation, Unicode, and repeated text are
retained. Adjacent intervals with identical wording stay separate so each can
be traced to its input cue numbers. The tool does not insert language labels,
deduplicate shared words, infer which language either input contains, or infer
that two temporally overlapping cues translate one another.

Use the existing [caption media workflow](caption-media.md) to append the draft
as one selectable subtitle stream to a local video. For example:

```sh
MEDIA="$TARGET/native/debug/build/cmd/caption_media/caption_media.exe"
"$MEDIA" attach 'Bilingual review/captions.json' episode.mp4 mul 'English + Chinese' 'Captioned review'
```

`mul` is an explicit multilingual metadata choice, not language detection. Both
languages share one stream and are selected together. To let viewers select
each independently, attach the separate original drafts instead. A player may
wrap or reorder visual lines according to its own font, layout and bidirectional
text support. No pixel-level positioning or particular player's rendering is
promised; inspect the actual viewing surface before delivery.

## Preview and saved evidence

`preview` writes nothing. It returns the full combined draft, per-interval
one-based primary/secondary cue references, original `source_file` labels,
input SHA-256 values, and four coverage totals. The totals sum to the declared
duration. An absent cue-reference field means that input has no active cue in
that interval. Primary-only or secondary-only coverage shows a timing difference;
it does not prove a missing translation. Matching declared duration also does
not prove that the inputs describe the same media or are correctly synchronized.
Use existing `caption_edit shift` or `sync`, listen, and preview again as needed.

`export` creates a new folder containing:

- `captions.json`: ordinary editable `mooncast.caption-draft.v1`
- `captions.srt` and `captions.vtt`: reusable UTF-8 subtitle sidecars
- `primary.json` and `secondary.json`: exact original input bytes
- `composition.json`: the preview report, written last

The new draft's `source_file` identifies a composition rather than pretending
to be either original. Both original labels, paths, hashes and cue references
remain in the report, and exact originals make the operation reproducible.
The report describes the initial result; after editing, keep it as history,
not as a claim that later output still has those original interval mappings.

## Practical limits and recovery

- Both inputs must be existing plain caption drafts with the same known
  `duration_ms`, from 1 ms to two hours. Each local UTF-8 JSON file is at most
  2 MiB; each draft has 1–5000 cues under the ordinary caption validator.
- Cues may overlap between inputs. Within either input, overlapping cues are
  refused with the input side and cue number. First merge simultaneous speaker
  lines or retime the input with the caption editor; no speaker is silently
  discarded or selected. Adjacent cues are allowed.
- The result is limited to 5000 display intervals and 2000 UTF-16 code units
  per combined cue, including the inserted newline. Combining two valid drafts
  can exceed these limits. Exports retain the existing 2 MiB sidecar limits.
  Shorten or simplify the source drafts if the full result cannot fit.
- No rounding, cue matching, gap filling, minimum display duration, automatic
  line wrapping, or readability certification occurs. A 1 ms boundary remains
  1 ms; small timing differences can create flashes. Review and retime inputs
  deliberately rather than trusting the composition as editorial approval.
- Input paths must name regular local files, not symlinks or URLs. The output
  parent must exist and its new folder must be unused, including by a dangling
  symlink. Spaces and Unicode in permitted paths are supported.

All derivative validation and the input-change check finish before the output
folder is created. Inputs and existing outputs are never overwritten. A disk
or permission failure during writes can leave a partial folder. Retain it for
diagnosis and use a fresh folder after correcting the problem; do not treat
an export without `composition.json` as complete. No cleanup is attempted.

This local workflow does not change a live project, generate translations,
grant rights, make a production decision, send a review, or publish. Focused
tests and a tiny real MP4 subtitle roundtrip establish local interchange only,
not external access, client acceptance, arbitrary-player accessibility, or
cumulative product qualification.
