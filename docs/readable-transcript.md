# Export a readable, chapter-organized transcript

Use `cmd/readable_transcript` to turn captions and chapter markers for the same
finished cut into a portable reading handoff. The HTML opens offline, with a
chapter contents list, keyboard-operable links, cue timestamps, semantic headings
and preserved multiline text. Plain text is included for search, copying and
printing. It does not need the Studio delivery host or a media player.

Build with the pinned graph and an absolute external target:

```sh
moon --target-dir /absolute/external/mooncast-build build cmd/readable_transcript --target native --frozen --strip -j 1
/absolute/external/mooncast-build/native/debug/build/cmd/readable_transcript/readable_transcript.exe preview fixtures/readable-transcript.captions.json fixtures/readable-transcript.chapters.json 'Episode review'
/absolute/external/mooncast-build/native/debug/build/cmd/readable_transcript/readable_transcript.exe export fixtures/readable-transcript.captions.json fixtures/readable-transcript.chapters.json 'Episode review' /tmp/episode-review
```

Choose a fresh prefix in an existing directory. Preview validates every export
format and prints the transcript without creating files. Export creates:

- `.transcript.html`: one standalone HTML document; no scripts, remote fonts,
  images, network requests or media controls
- `.transcript.txt`: chapter headings, exact millisecond cue times and wording
- `.transcript.json`: exact input paths and SHA-256 hashes, original parsed drafts,
  title, chapter ranges and cue/continuation mapping

You can prepare the drafts with `caption_edit` and `chapters`, or preserve them
through a recut using `caption_conform` and `chapter_conform`. See
[caption editing](caption-editing.md), [chapter authoring](timeline-chapters.md)
and [chapter conforming](chapter-conforming.md). Edit the source drafts and
export to a fresh prefix when correcting wording or chapter titles. The output
report describes only those input bytes; it does not update after later edits.

## How chapters and cues join

Both drafts must describe the same output from time zero. You choose the binding;
equal duration does not prove media identity. Chapter project/timeline IDs and
revisions, caption source label, and exact file hashes remain inspectable in the
JSON. No media is opened, checked, transcribed or rendered.

The caption clock is milliseconds. Chapter clocks may differ, but duration and
all marker starts must convert to exact whole milliseconds. For example 24 ticks
at 24 ticks/second is supported; one tick at that rate fails rather than rounding.
The two complete durations must match exactly.

A cue belongs to the chapter containing its start, using half-open ranges. A cue
starting exactly at a new chapter belongs there. If it extends into subsequent
chapters, those chapters contain a link/reference to the original cue. Its text
is printed exactly once, without guessed word splits, clipping or duplication.
A cue ending exactly at a chapter start does not continue into it. Overlapping
cues retain their original order and intervals, including equal start times.

An unchaptered lead-in gets a “Before first chapter” section. Chapters with no
starting cues stay visible, including any continuation links; their empty message
does not claim the media is silent. Gaps remain gaps. The synthetic fixture
includes a lead-in, overlapping multiline Unicode text, an exact-boundary cue,
a chapter with continuation but no new cue, and titles needing HTML escaping.
Generated navigation IDs come from ordinal positions, never user text.

## Scope and limits

This is a local preparation aid for MOONCAST-R02/N05, not accessibility
certification, client acceptance, delivery confirmation or publication. Inspect
wording and timing against the intended media and verify recipient access before
sharing any file. No upload, approval, provider call or project mutation occurs.
The report includes local absolute paths; review it before sharing externally.
HTML can be read and searched with ordinary browser controls but does not seek
media, translate, edit or synchronize with playback. No screen-reader or visual
browser qualification is claimed by the native focused tests. The document does
not guess the language of multilingual captions.

Input limits: caption JSON 16 MiB, chapter JSON 2 MiB; 1–5000 valid plain-text cues,
1–1000 ordered chapters, at most two hours, and at most 20000 continuation
references. Existing validators reject invalid ordering, duplicate chapter IDs,
empty cues, markup captions and unsupported controls. Titles are nonblank single
lines up to 200 UTF-16 code units. Each output is limited to 32 MiB. JSON parsing
retains the repository's normal duplicate-key/unknown-field behavior; use clear,
unambiguous documents. HTML escapes text and titles instead of interpreting them.

All payloads and destination names are checked before any write. Existing files,
directories and dangling symlinks are refused. Writes also use exclusive creation.
A later I/O error or concurrent file creation can leave a partial new bundle;
preserve it and use a new prefix after resolving the cause. No output or input is
overwritten or removed. SHA-256 records the bytes read, not authorship, rights or
atomic locking of source files.
