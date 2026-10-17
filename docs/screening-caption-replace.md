# Previewed caption wording replacement

MoonCast's offline screening player now replaces repeated wording across the applied caption draft. This supports the editor's coherent-master inspection and correction workflow in the current MoonCast PRD (editor job; graph/editor/review tools). The original cut, rights, QC and client acceptance remain separate.

1. Open an exported screening player with captions. In Caption corrections, find **Replace caption wording**.
2. Enter literal, case-sensitive text and its replacement. Empty replacement deletes matching text; the resulting captions must still satisfy the existing caption rules.
3. Choose **Preview replacements**. Read each before/after pair. Nothing changes yet. Matches include captions hidden by transcript search.
4. Choose **Apply previewed replacements**. Timings and cue order remain unchanged. Transcript rows and player captions use the corrected text.
5. Download corrected JSON or WebVTT through the existing caption download buttons. Closing the page without downloading loses session changes. Original screening files are not rewritten.

Example: replace `Moon` with `Lunar` across repeated names, preview all changed captions, then apply. Replacement is literal: `$&` stays `$&`; there are no regular expressions or word-boundary inference. A caption containing `Moonlight` becomes `Lunarlight`.

Finish or cancel an unsaved single-caption edit first. If captions or replacement inputs change after preview, preview again. Any invalid result rejects the whole proposed replacement. This feature does not send feedback or claim a reviewed master.

## Focused evidence and limits

`node --test scripts/test-screening-caption-replace.cjs` exercises the exact embedded production player script with DOM/media/download doubles, including before/after preview, literal replacement, Unicode, hidden cues, stale changes, edited selection, unchanged timing, and existing JSON/WebVTT output. Existing screening script tests remain the regression path. No real browser, native build, client review or live media decoder qualification is implied.
