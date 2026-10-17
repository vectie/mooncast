///|
fn escape_html(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///|
/// Embedded data avoids local-file fetch/CORS requirements. Never insert raw HTML.
fn script_data(plan : Plan) -> String {
  plan
  .to_json()
  .stringify()
  .replace_all(old="<", new="\\u003c")
  .replace_all(old=">", new="\\u003e")
  .replace_all(old="&", new="\\u0026")
}

///|
fn player_script() -> String {
  let script =
    #|(() => {
    #|  'use strict';
    #|  const data = JSON.parse(document.getElementById('screening-data').textContent);
    #|  const video = document.getElementById('player');
    #|  const status = document.getElementById('playback-status');
    #|  const search = document.getElementById('search');
    #|  const count = document.getElementById('search-count');
    #|  const captionButton = document.getElementById('captions-toggle');
    #|  const fallback = document.getElementById('caption-fallback');
    #|  const cueRows = Array.from(document.querySelectorAll('[data-cue-index]'));
    #|  const chapterButtons = Array.from(document.querySelectorAll('[data-chapter-index]'));
    #|  let pendingSeek = null;
    #|  let captionsOn = data.cues.length > 0;
    #|  let track = null;
    #|  const captionCues = data.cues.map(cue => ({...cue}));
    #|  const captionTrackCues = [];
    #|  let captionPreview = null;
    #|  function displayedCaption(index) { return captionPreview && captionPreview.index === index ? captionPreview.cue : captionCues[index]; }
    #|  const rangeStatus = document.getElementById('range-status');
    #|  const repeatButton = document.getElementById('range-repeat');
    #|  let rangeStart = null, rangeEnd = null, repeating = false, repeatRevision = 0;
    #|  function rangeClock(ms) { return (ms / 1000).toFixed(3) + ' s'; }
    #|  function mediaEnd() { return Number.isFinite(video.duration) ? Math.min(video.duration * 1000, data.duration_ms) : data.duration_ms; }
    #|  function validRange() { return rangeStart !== null && rangeEnd !== null && rangeStart < rangeEnd && rangeEnd <= mediaEnd(); }
    #|  function showRange(message = '') {
    #|    repeatButton.disabled = !validRange();
    #|    repeatButton.setAttribute('aria-pressed', String(repeating));
    #|    repeatButton.textContent = repeating ? 'Repeat on' : 'Repeat off';
    #|    rangeStatus.textContent = message || ('A: ' + (rangeStart === null ? 'unset' : rangeClock(rangeStart)) + ' · B: ' + (rangeEnd === null ? 'unset' : rangeClock(rangeEnd)) + (repeating ? '. Repeating while playing.' : '. Mark A then B; turn on repeat and press Play.'));
    #|  }
    #|  function stopRepeat(message = '') { repeating = false; repeatRevision += 1; showRange(message); }
    #|  function markRange(end) {
    #|    if (video.readyState === 0 || !Number.isFinite(video.currentTime)) { showRange('Load the video and choose a position before marking a range.'); return; }
    #|    const position = Math.max(0, Math.min(Math.round(video.currentTime * 1000), mediaEnd()));
    #|    if (end && (rangeStart === null || position <= rangeStart)) { showRange('Mark A first, then mark B at a later position. The previous range is unchanged.'); return; }
    #|    if (end) rangeEnd = position;
    #|    else { rangeStart = position; if (rangeEnd !== null && rangeEnd <= rangeStart) rangeEnd = null; }
    #|    stopRepeat();
    #|  }
    #|  document.getElementById('range-start').addEventListener('click', () => markRange(false));
    #|  document.getElementById('range-end').addEventListener('click', () => markRange(true));
    #|  document.getElementById('range-clear').addEventListener('click', () => { rangeStart = null; rangeEnd = null; stopRepeat(); });
    #|  repeatButton.addEventListener('click', () => {
    #|    if (repeating) { stopRepeat(); return; }
    #|    if (!validRange() || video.readyState === 0) { showRange('Choose a valid loaded A–B range first.'); return; }
    #|    repeating = true; repeatRevision += 1;
    #|    if (video.currentTime * 1000 < rangeStart || video.currentTime * 1000 >= rangeEnd) seek(rangeStart);
    #|    showRange();
    #|  });
    #|  video.addEventListener('timeupdate', () => {
    #|    if (!repeating) return;
    #|    if (!validRange()) { stopRepeat('The media duration changed. Mark a new range.'); return; }
    #|    if (!video.paused && !video.seeking && video.currentTime * 1000 >= rangeEnd) seek(rangeStart);
    #|  });
    #|  video.addEventListener('seeking', () => {
    #|    if (repeating && (video.currentTime * 1000 < rangeStart || video.currentTime * 1000 > rangeEnd)) stopRepeat('Repeat stopped after seeking outside the range.');
    #|  });
    #|  video.addEventListener('ended', () => {
    #|    if (!repeating || !validRange()) return;
    #|    const revision = repeatRevision;
    #|    seek(rangeStart);
    #|    if (!repeating) return;
    #|    try {
    #|      const playback = video.play();
    #|      if (playback && typeof playback.catch === 'function') playback.catch(() => { if (revision === repeatRevision) stopRepeat('Repeat could not resume. Press Play to continue.'); });
    #|    } catch (_) { stopRepeat('Repeat could not resume. Press Play to continue.'); }
    #|  });
    #|  video.addEventListener('durationchange', () => { if (repeating && !validRange()) stopRepeat('The media duration changed. Mark a new range.'); else showRange(); });
    #|  video.addEventListener('error', () => stopRepeat('Repeat stopped because the media could not play.'));
    #|  showRange();
    #|  function clock(ms) {
    #|    const seconds = Math.floor(ms / 1000);
    #|    return String(Math.floor(seconds / 3600)).padStart(2, '0') + ':' + String(Math.floor(seconds / 60) % 60).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
    #|  }
    #|  function update() {
    #|    const ms = Math.floor(video.currentTime * 1000);
    #|    const active = [];
    #|    cueRows.forEach((row, index) => {
    #|      const cue = displayedCaption(index);
    #|      const current = cue.start_ms <= ms && ms < cue.end_ms;
    #|      row.classList.toggle('current', current);
    #|      if (current) { row.setAttribute('aria-current', 'true'); active.push(cue.text); }
    #|      else row.removeAttribute('aria-current');
    #|    });
    #|    chapterButtons.forEach((button, index) => {
    #|      const chapter = data.chapters[index];
    #|      const end = index + 1 < data.chapters.length ? data.chapters[index + 1].start_ms : data.duration_ms;
    #|      const current = chapter.start_ms <= ms && ms < end;
    #|      button.classList.toggle('current', current);
    #|      if (current) button.setAttribute('aria-current', 'true');
    #|      else button.removeAttribute('aria-current');
    #|    });
    #|    fallback.textContent = active.join('\n');
    #|    fallback.hidden = !captionsOn || track !== null || active.length === 0;
    #|  }
    #|  function seek(ms) {
    #|    const duration = Number.isFinite(video.duration) ? Math.min(video.duration * 1000, data.duration_ms) : data.duration_ms;
    #|    const target = Math.max(0, Math.min(ms, duration));
    #|    if (video.readyState === 0) {
    #|      pendingSeek = target;
    #|      status.textContent = 'Loading video; selected position ' + clock(target) + '.';
    #|      video.load();
    #|      return;
    #|    }
    #|    try { video.currentTime = target / 1000; status.textContent = 'Position ' + clock(target) + (video.paused ? '. Press Play to continue.' : '. Playback continues.'); update(); }
    #|    catch (_) { stopRepeat('Repeat stopped because the selected position could not be reached.'); status.textContent = 'Unable to seek. Open media.mp4 directly or try another local browser.'; }
    #|  }
    #|  // Local issue notes are bound to the exact copied media and screening plan.
    #|  // They are never client acceptance, author identity, or publication authority.
    #|  const noteList = document.getElementById('review-notes');
    #|  if (noteList) {
    #|    const noteStatus = document.getElementById('review-status');
    #|    const noteText = document.getElementById('review-text');
    #|    const noteAnchor = document.getElementById('review-anchor');
    #|    const noteSave = document.getElementById('review-save');
    #|    const noteFilter = document.getElementById('review-filter');
    #|    const noteSearch = document.getElementById('review-search');
    #|    const noteChapter = document.getElementById('review-chapter');
    #|    const noteOrder = document.getElementById('review-order');
    #|    const notePrevious = document.getElementById('review-previous');
    #|    const noteNext = document.getElementById('review-next');
    #|    const noteNavigation = document.getElementById('review-navigation');
    #|    const briefScope = document.getElementById('review-brief-scope');
    #|    const briefButton = document.getElementById('review-brief-download');
    #|    const briefStatus = document.getElementById('review-brief-status');
    #|    let briefURL = null;
    #|    briefScope.value = 'matching';
    #|    let selectedIssue = null;
    #|    const scopes = [{title: 'All chapters', start: 0, end: data.duration_ms}];
    #|    if (data.chapters.length && data.chapters[0].start_ms > 0) scopes.push({title: 'Before first chapter', start: 0, end: data.chapters[0].start_ms});
    #|    data.chapters.forEach((chapter, index) => scopes.push({title: (index + 1) + '. ' + chapter.title, start: chapter.start_ms, end: index + 1 < data.chapters.length ? data.chapters[index + 1].start_ms : data.duration_ms}));
    #|    scopes.forEach((scope, index) => { const option = document.createElement('option'); option.value = String(index); option.textContent = scope.title; noteChapter.appendChild(option); });
    #|    noteChapter.value = '0'; noteOrder.value = 'created';
    #|    function timelineCompare(a, b) { return a.start_ms - b.start_ms || a.id - b.id; }
    #|    function matchingNotes() {
    #|      const query = noteSearch.value.trim().toLowerCase(), scope = scopes[Number(noteChapter.value)] || scopes[0];
    #|      return notes.filter(note => {
    #|        const statusMatches = !((noteFilter.value === 'open' && note.resolved) || (noteFilter.value === 'resolved' && !note.resolved));
    #|        const inChapter = note.end_ms === null ? note.start_ms >= scope.start && (note.start_ms < scope.end || scope.end === data.duration_ms && note.start_ms === scope.end) : note.start_ms < scope.end && note.end_ms > scope.start;
    #|        return statusMatches && inChapter && note.text.toLowerCase().includes(query);
    #|      });
    #|    }
    #|    function adjacentIssue(direction) {
    #|      const ordered = matchingNotes().sort(timelineCompare);
    #|      if (!selectedIssue) return direction > 0 ? ordered[0] : undefined;
    #|      return direction > 0 ? ordered.find(note => timelineCompare(note, selectedIssue) > 0) : ordered.reverse().find(note => timelineCompare(note, selectedIssue) < 0);
    #|    }
    #|    function showNavigation() {
    #|      notePrevious.disabled = !adjacentIssue(-1); noteNext.disabled = !adjacentIssue(1);
    #|      noteNavigation.textContent = selectedIssue ? 'Selected issue #' + selectedIssue.id + ' at ' + noteClock(selectedIssue.start_ms) + '. Previous/next follows matching issues in timeline order; no wrapping.' : 'Choose Next matching issue to begin at the earliest match. Previous/next follows timeline order; no wrapping.';
    #|    }
    #|    function visitIssue(note) { selectedIssue = {id: note.id, start_ms: note.start_ms}; stopRepeat(); seek(note.start_ms); renderNotes(); }
    #|    notePrevious.addEventListener('click', () => { const note = adjacentIssue(-1); if (note) visitIssue(note); });
    #|    noteNext.addEventListener('click', () => { const note = adjacentIssue(1); if (note) visitIssue(note); });
    #|    function resetTriage() { selectedIssue = null; renderNotes(); }
    #|    noteSearch.addEventListener('input', resetTriage);
    #|    noteChapter.addEventListener('change', resetTriage);
    #|    noteOrder.addEventListener('change', () => renderNotes());
    #|    const noteFile = document.getElementById('review-file');
    #|    const noteApply = document.getElementById('review-apply');
    #|    const noteMerge = document.getElementById('review-merge');
    #|    const noteDiscard = document.getElementById('review-discard-import');
    #|    const mergePreview = document.getElementById('review-merge-preview');
    #|    const noteImportStatus = document.getElementById('review-import-status');
    #|    const revisionOpen = document.getElementById('review-revision-open');
    #|    const revisionPanel = document.getElementById('review-revision-panel');
    #|    const revisionList = document.getElementById('review-revision-list');
    #|    const revisionStatus = document.getElementById('review-revision-status');
    #|    const revisionApply = document.getElementById('review-revision-apply');
    #|    let pendingRevision = null;
    #|    const source = {media_sha256: document.getElementById('screening-source-sha256').textContent, plan_json: JSON.stringify(data)};
    #|    let notes = [], editing = null, anchor = null, revision = 0, lastDownload = -1, importEpoch = 0, pendingImport = null, downloadURL = null;
    #|    const undoButton = document.getElementById('review-undo'), redoButton = document.getElementById('review-redo');
    #|    const historyStatus = document.getElementById('review-history-status');
    #|    let history = [{json: '[]', label: ''}], historyIndex = 0;
    #|    function hasDraft() { return editing !== null || anchor !== null || noteText.value !== ''; }
    #|    function showHistory() {
    #|      const draft = hasDraft();
    #|      undoButton.disabled = historyIndex === 0 || draft;
    #|      redoButton.disabled = historyIndex === history.length - 1 || draft;
    #|      undoButton.textContent = historyIndex ? 'Undo: ' + history[historyIndex].label : 'Undo notebook change';
    #|      redoButton.textContent = historyIndex < history.length - 1 ? 'Redo: ' + history[historyIndex + 1].label : 'Redo notebook change';
    #|      historyStatus.textContent = historyIndex + ' undo / ' + (history.length - historyIndex - 1) + ' redo steps retained. ' + (draft ? 'Save or Cancel edit before using history. ' : '') + 'Session only; up to 20 changes and 8 MiB of serialized UTF-16 history. Downloads and editor drafts are not restored.';
    #|    }
    #|    function rememberChange(label) {
    #|      const json = JSON.stringify(notes);
    #|      if (json === history[historyIndex].json) return;
    #|      history = history.slice(0, historyIndex + 1);
    #|      history.push({json, label});
    #|      let units = history.reduce((total, state) => total + state.json.length, 0);
    #|      while (history.length > 21 || units > 4 * 1024 * 1024 && history.length > 1) units -= history.shift().json.length;
    #|      historyIndex = history.length - 1;
    #|    }
    #|    function restoreHistory(direction) {
    #|      if (hasDraft()) { showHistory(); return; }
    #|      const next = historyIndex + direction;
    #|      if (next < 0 || next >= history.length) return;
    #|      const label = direction < 0 ? history[historyIndex].label : history[next].label;
    #|      notes = JSON.parse(history[next].json); historyIndex = next;
    #|      if (selectedIssue) { const note = notes.find(note => note.id === selectedIssue.id); selectedIssue = note ? {id: note.id, start_ms: note.start_ms} : null; }
    #|      revision += 1; invalidateImport(); noteImportStatus.textContent = '';
    #|      renderNotes((direction < 0 ? 'Undid ' : 'Redid ') + label + '. Saved notebook notes restored; existing downloaded files are unchanged. Download again to keep this state.');
    #|    }
    #|    undoButton.addEventListener('click', () => restoreHistory(-1));
    #|    redoButton.addEventListener('click', () => restoreHistory(1));
    #|    noteText.addEventListener('input', showHistory);
    #|    function noteClock(ms) { return clock(ms) + '.' + String(ms % 1000).padStart(3, '0'); }
    #|    function spanLabel(note) { return noteClock(note.start_ms) + (note.end_ms === null ? '' : '–' + noteClock(note.end_ms)); }
    #|    function showAnchor() { noteAnchor.textContent = anchor ? 'Note at ' + spanLabel(anchor) : 'Capture a position or the marked A–B range before saving a note.'; noteSave.textContent = editing === null ? 'Add note' : 'Save note changes'; showRevisionSelection(); showHistory(); }
    #|    function invalidateImport() { clearRevision(); revisionOpen.disabled = true; pendingImport = null; noteApply.disabled = true; noteMerge.disabled = true; noteDiscard.disabled = true; mergePreview.replaceChildren(); importEpoch += 1; }
    #|    function resetEditor() { editing = null; anchor = null; noteText.value = ''; showAnchor(); }
    #|    function changed(message, label = 'Saved notebook change') { rememberChange(label); revision += 1; invalidateImport(); noteImportStatus.textContent = ''; renderNotes(message); }
    #|    function button(label, action) { const node = document.createElement('button'); node.type = 'button'; node.textContent = label; node.addEventListener('click', action); return node; }
    #|    function renderNotes(message = '') {
    #|      noteList.replaceChildren();
    #|      let shown = 0;
    #|      const visible = matchingNotes();
    #|      if (noteOrder.value === 'timeline') visible.sort(timelineCompare);
    #|      visible.forEach(note => {
    #|        shown += 1;
    #|        const row = document.createElement('li');
    #|        row.appendChild(button('#' + note.id + ' · ' + spanLabel(note) + (note.resolved ? ' · Resolved' : ' · Open'), () => visitIssue(note)));
    #|        if (selectedIssue && note.id === selectedIssue.id) { row.classList.toggle('current', true); row.setAttribute('aria-current', 'true'); }
    #|        const words = document.createElement('p'); words.className = 'words'; words.textContent = note.text; row.appendChild(words);
    #|        const actions = document.createElement('div'); actions.className = 'controls';
    #|        actions.appendChild(button('Edit note', () => { editing = note.id; anchor = {start_ms: note.start_ms, end_ms: note.end_ms}; noteText.value = note.text; showAnchor(); noteText.focus(); }));
    #|        actions.appendChild(button(note.resolved ? 'Reopen issue' : 'Resolve issue', () => { note.resolved = !note.resolved; changed('Issue status changed locally.', note.resolved ? 'Resolve issue' : 'Reopen issue'); }));
    #|        row.appendChild(actions); noteList.appendChild(row);
    #|      });
    #|      showNavigation(); showBrief(); showHistory();
    #|      noteStatus.textContent = (message ? message + ' ' : '') + shown + ' shown / ' + notes.length + ' notes; ' + notes.filter(note => !note.resolved).length + ' open. ' + (revision === lastDownload ? 'No changes since the last download request.' : 'Download a notebook to keep these notes.') + ' No automatic storage or sending.';
    #|    }
    #|    document.getElementById('review-point').addEventListener('click', () => {
    #|      if (video.readyState === 0 || !Number.isFinite(video.currentTime)) { noteStatus.textContent = 'Load the video and choose a position first.'; return; }
    #|      anchor = {start_ms: Math.max(0, Math.min(Math.round(video.currentTime * 1000), Math.floor(mediaEnd()))), end_ms: null}; showAnchor();
    #|    });
    #|    document.getElementById('review-range').addEventListener('click', () => {
    #|      if (!validRange() || !Number.isSafeInteger(rangeStart) || !Number.isSafeInteger(rangeEnd)) { noteStatus.textContent = 'Mark a valid A–B range first. The note is unchanged.'; return; }
    #|      anchor = {start_ms: rangeStart, end_ms: rangeEnd}; showAnchor();
    #|    });
    #|    document.getElementById('review-cancel').addEventListener('click', resetEditor);
    #|    noteSave.addEventListener('click', () => {
    #|      if (!anchor || !noteText.value.trim() || noteText.value.length > 2000 || /\u0000/.test(noteText.value)) { noteStatus.textContent = 'Capture a position or range and enter 1–2000 characters of nonblank text without NUL.'; return; }
    #|      if (editing === null && notes.length >= 500) { noteStatus.textContent = 'This notebook is limited to 500 notes.'; return; }
    #|      const actionLabel = editing === null ? 'Add note' : 'Edit note';
    #|      if (editing === null) { let id = 1; while (notes.some(note => note.id === id)) id += 1; notes.push({id, ...anchor, text: noteText.value, resolved: false}); }
    #|      else { const note = notes.find(note => note.id === editing); Object.assign(note, anchor, {text: noteText.value}); if (selectedIssue && selectedIssue.id === note.id) selectedIssue = {id: note.id, start_ms: note.start_ms}; }
    #|      resetEditor(); changed('Note saved in this page session.', actionLabel);
    #|    });
    #|    noteFilter.addEventListener('change', resetTriage);
    #|    document.getElementById('review-download').addEventListener('click', () => {
    #|      try {
    #|        const notebook = {contract: 'mooncast.screening-notebook.v1', source, notes};
    #|        const blob = new Blob([JSON.stringify(notebook, null, 2) + '\n'], {type: 'application/json'});
    #|        if (blob.size > 64 * 1024 * 1024) throw Error('Notebook exceeds 64 MiB');
    #|        if (downloadURL) URL.revokeObjectURL(downloadURL);
    #|        downloadURL = URL.createObjectURL(blob);
    #|        const link = document.createElement('a'); link.href = downloadURL; link.download = 'screening-notes.json'; document.body.appendChild(link); link.click(); link.remove();
    #|        lastDownload = revision; renderNotes('Notebook download requested; check that your browser saved the file. Uncommitted text in the editor is not included.');
    #|      } catch (_) { noteStatus.textContent = 'This browser could not download the notebook. Your notes remain here; try again before closing this page.'; }
    #|    });
    #|    // A readable snapshot of saved editorial notes, separate from the reloadable notebook.
    #|    function briefNotes() { return (briefScope.value === 'all' ? notes.slice() : matchingNotes()).sort(timelineCompare); }
    #|    function showBrief() {
    #|      const selected = briefNotes();
    #|      briefButton.disabled = selected.length === 0;
    #|      briefStatus.textContent = selected.length + ' of ' + notes.length + ' saved notes in this brief; ' + (notes.length - selected.length) + ' omitted. Timeline order. Includes saved wording and supplied caption/chapter context; excludes editor drafts. Download notebook separately to resume editing.';
    #|    }
    #|    briefScope.addEventListener('change', showBrief);
    #|    function briefEscape(value) { return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;'); }
    #|    function briefExcerpt(text) {
    #|      const characters = Array.from(text);
    #|      return briefEscape(characters.slice(0, 600).join('')) + (characters.length > 600 ? ' [excerpt shortened]' : '');
    #|    }
    #|    function briefIntersects(note, start, end, terminal = false) {
    #|      return note.end_ms === null ? note.start_ms >= start && (note.start_ms < end || terminal && note.start_ms === end) : note.start_ms < end && note.end_ms > start;
    #|    }
    #|    function briefContext(note) {
    #|      const chapters = scopes.slice(1).filter(scope => briefIntersects(note, scope.start, scope.end, scope.end === data.duration_ms));
    #|      const cues = data.cues.filter(cue => briefIntersects(note, cue.start_ms, cue.end_ms));
    #|      let html = '<h3>Supplied chapter context</h3>';
    #|      html += chapters.length ? '<ul>' + chapters.slice(0, 12).map(chapter => '<li>' + briefExcerpt(chapter.title) + '</li>').join('') + '</ul>' : '<p>No chapter draft supplied.</p>';
    #|      if (chapters.length > 12) html += '<p>' + (chapters.length - 12) + ' more overlapping chapter labels omitted.</p>';
    #|      html += '<h3>Supplied caption context</h3>';
    #|      html += cues.length ? '<ul>' + cues.slice(0, 8).map(cue => '<li><span class="time">' + noteClock(cue.start_ms) + '–' + noteClock(cue.end_ms) + '</span><p class="words">' + briefExcerpt(cue.text) + '</p></li>').join('') + '</ul>' : '<p>No supplied caption overlaps this ' + (note.end_ms === null ? 'point' : 'range') + '.</p>';
    #|      if (cues.length > 8) html += '<p>' + (cues.length - 8) + ' more overlapping caption cues omitted. Inspect the screening for complete context.</p>';
    #|      return html;
    #|    }
    #|    function feedbackBrief(selected) {
    #|      const scope = scopes[Number(noteChapter.value)] || scopes[0];
    #|      const filters = briefScope.value === 'all' ? 'All saved notes. Triage filters ignored.' : 'Current matches. Status: ' + ({all: 'All', open: 'Open', resolved: 'Resolved'}[noteFilter.value] || 'All') + '; chapter: ' + scope.title + '; note text contains: ' + (noteSearch.value.trim() ? JSON.stringify(noteSearch.value.trim()) : '(any text)') + '.';
    #|      const open = selected.filter(note => !note.resolved).length;
    #|      let html = '<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; base-uri \'none\'; form-action \'none\'"><title>' + briefEscape(data.title) + ' — Feedback brief</title><style>';
    #|      html += 'body{max-width:60rem;margin:2rem auto;padding:0 1.2rem;color:#172326;background:white;font:16px/1.5 system-ui,sans-serif}h1{line-height:1.2}h2{font-size:1.2rem}h3{font-size:1rem;margin-bottom:.2rem}.words{white-space:pre-wrap;overflow-wrap:anywhere}.time{font-variant-numeric:tabular-nums}dd{margin:0 0 .6rem;overflow-wrap:anywhere}dt{font-weight:bold}article{border-top:1px solid #98a7ab;padding:1rem 0}li p{margin:.2rem 0}footer{border-top:1px solid #98a7ab;font-size:.9rem}@media print{body{max-width:none;margin:0;font-size:11pt}h2,h3{break-after:avoid}p,li{orphans:3;widows:3}article{break-inside:auto}}';
    #|      html += '</style></head><body><header><h1>' + briefEscape(data.title) + '</h1><p>Editorial feedback brief · saved-note snapshot</p><dl><dt>Recorded media SHA-256</dt><dd>' + briefEscape(source.media_sha256) + '</dd><dt>Screening duration</dt><dd>' + noteClock(data.duration_ms) + '</dd><dt>Included scope</dt><dd class="words">' + briefEscape(filters) + '</dd></dl><p>' + selected.length + ' of ' + notes.length + ' saved notes included; ' + (notes.length - selected.length) + ' omitted. Included: ' + open + ' open, ' + (selected.length - open) + ' resolved. Timeline order, then local note ID.</p><p>Uncommitted editor text is excluded. IDs belong to this local notebook; no reviewer identity or acceptance is authenticated. Resolved means a local issue status only.</p></header><main>';
    #|      selected.forEach(note => {
    #|        html += '<article><h2>Issue #' + note.id + ' · <span class="time">' + spanLabel(note) + '</span> · ' + (note.resolved ? 'Resolved' : 'Open') + ' · ' + (note.end_ms === null ? 'Point' : 'Range') + '</h2><p class="words">' + briefEscape(note.text) + '</p>' + briefContext(note) + '</article>';
    #|      });
    #|      return html + '</main><footer><p>Local editorial reference only. This snapshot contains no media, automatic updates, client acceptance, rights clearance, QC approval, delivery receipt or publication permission. The recorded digest identifies the exported cut; this report does not rehash media or authenticate the copied folder. Caption and chapter context is operator-supplied, not verified speech or scene recognition.</p><p>Point context uses half-open caption/chapter intervals; a terminal point belongs to the final chapter. Range context includes positive overlaps, never just touching endpoints. Context shows at most 12 chapter labels and 8 caption cues per note, each limited to 600 Unicode code points with omissions marked. Note text and anchors are not shortened. Keep the full notebook JSON and screening folder to continue review. Use your browser’s Print command for a paper or PDF copy; this HTML cannot be reloaded as a notebook.</p></footer></body></html>\n';
    #|    }
    #|    briefButton.addEventListener('click', () => {
    #|      const selected = briefNotes();
    #|      if (!selected.length) { showBrief(); return; }
    #|      try {
    #|        const blob = new Blob([feedbackBrief(selected)], {type: 'text/html;charset=utf-8'});
    #|        if (blob.size > 16 * 1024 * 1024) throw Error('Feedback brief exceeds 16 MiB');
    #|        const url = URL.createObjectURL(blob);
    #|        if (briefURL) URL.revokeObjectURL(briefURL);
    #|        briefURL = url;
    #|        const link = document.createElement('a'); link.href = briefURL; link.download = 'screening-feedback.html'; document.body.appendChild(link);
    #|        try { link.click(); } finally { link.remove(); }
    #|        briefStatus.textContent = 'Feedback brief download requested for ' + selected.length + ' of ' + notes.length + ' saved notes; check that your browser saved screening-feedback.html. Open it to read or print. Download notebook separately to keep editable notes.';
    #|      } catch (_) { briefStatus.textContent = 'This browser could not download the feedback brief. Notes and editor draft remain unchanged; try again or download the notebook before closing.'; }
    #|    });
    #|    function validateNotebook(value) {
    #|      if (!value || value.contract !== 'mooncast.screening-notebook.v1' || !value.source || value.source.media_sha256 !== source.media_sha256 || value.source.plan_json !== source.plan_json) throw Error('This notebook belongs to different media or a different screening plan.');
    #|      if (!Array.isArray(value.notes) || value.notes.length > 500) throw Error('A notebook must contain at most 500 notes.');
    #|      const ids = new Set();
    #|      return value.notes.map(note => {
    #|        if (!note || !Number.isSafeInteger(note.id) || note.id <= 0 || note.id >= Number.MAX_SAFE_INTEGER || ids.has(note.id) || !Number.isSafeInteger(note.start_ms) || note.start_ms < 0 || note.start_ms > data.duration_ms || !(note.end_ms === null || (Number.isSafeInteger(note.end_ms) && note.end_ms > note.start_ms && note.end_ms <= data.duration_ms)) || typeof note.text !== 'string' || !note.text.trim() || note.text.length > 2000 || /\u0000/.test(note.text) || typeof note.resolved !== 'boolean') throw Error('A note has an invalid ID, time, text or issue status.');
    #|        ids.add(note.id); return {id: note.id, start_ms: note.start_ms, end_ms: note.end_ms, text: note.text, resolved: note.resolved};
    #|      });
    #|    }
    #|    // IDs belong to one notebook only. Merge uses exact editorial content and
    #|    // status, never ID equality, author identity, majority vote or latest-wins.
    #|    function mergeNotebooks(loaded) {
    #|      const merged = notes.map(note => ({...note})), additions = [], conflicts = [], sourceIds = new Map(), seen = new Set(), wording = new Set(), ids = new Set(notes.map(note => note.id));
    #|      const contentKey = note => JSON.stringify([note.start_ms, note.end_ms, note.text]);
    #|      const exactKey = note => JSON.stringify([note.start_ms, note.end_ms, note.text, note.resolved]);
    #|      function rememberId(note, location) { const entries = sourceIds.get(note.id) || []; entries.push({key: exactKey(note), location}); sourceIds.set(note.id, entries); }
    #|      notes.forEach(note => { seen.add(exactKey(note)); wording.add(contentKey(note)); rememberId(note, 'Current notebook #' + note.id); });
    #|      let duplicates = 0, variants = 0, nextId = 1;
    #|      loaded.forEach(file => file.notes.forEach(note => {
    #|        const exact = exactKey(note), content = contentKey(note), duplicate = seen.has(exact);
    #|        const divergent = (sourceIds.get(note.id) || []).filter(entry => entry.key !== exact);
    #|        if (divergent.length) conflicts.push({file: file.name, id: note.id, prior: [...new Set(divergent.map(entry => entry.location))], duplicate});
    #|        rememberId(note, file.name + ' #' + note.id);
    #|        if (duplicate) { duplicates += 1; return; }
    #|        const variant = wording.has(content);
    #|        if (variant) variants += 1;
    #|        while (ids.has(nextId)) nextId += 1;
    #|        const added = {...note, id: nextId}; ids.add(nextId);
    #|        merged.push(added); additions.push({note: added, sourceId: note.id, file: file.name, variant});
    #|        seen.add(exact); wording.add(content);
    #|      }));
    #|      return {notes: merged, additions, duplicates, variants, conflicts};
    #|    }
    #|    // ID equality only proposes a correspondence. Nothing is selected until
    #|    // the editor inspects the exact before/after and chooses that change.
    #|    function clearRevision() { pendingRevision = null; revisionPanel.hidden = true; revisionList.replaceChildren(); revisionStatus.textContent = ''; revisionApply.disabled = true; }
    #|    function revisionChoices() { return pendingRevision && pendingRevision.revision === revision ? pendingRevision.candidates.filter(candidate => candidate.selected) : []; }
    #|    function showRevisionSelection() {
    #|      if (!pendingRevision) return;
    #|      const selected = revisionChoices(), additions = selected.filter(candidate => !candidate.before).length, updates = selected.length - additions;
    #|      const blockedDraft = selected.some(candidate => candidate.before && candidate.before.id === editing);
    #|      const total = notes.length + additions;
    #|      revisionApply.disabled = selected.length === 0 || total > 500 || blockedDraft;
    #|      revisionStatus.textContent = pendingRevision.name + ': ' + pendingRevision.candidates.length + ' proposed changes; ' + pendingRevision.unchanged + ' identical notes; ' + pendingRevision.currentOnly + ' current-only notes kept. Selected: ' + updates + ' replacements, ' + additions + ' additions; ' + (pendingRevision.candidates.length - selected.length) + ' proposals not selected. Result: ' + total + ' notes. ' + (total > 500 ? 'Cannot apply: result exceeds 500 notes. Deselect additions.' : blockedDraft ? 'Cannot apply: a selected issue is open in the note editor. Cancel that edit, or save it and review the file again.' : 'Unselected and current-only notes stay unchanged. No deletion or automatic status reconciliation.');
    #|    }
    #|    revisionOpen.addEventListener('click', () => {
    #|      if (!pendingImport || pendingImport.revision !== revision || pendingImport.loaded.length !== 1) return;
    #|      clearRevision();
    #|      const file = pendingImport.loaded[0], current = new Map(notes.map(note => [note.id, note]));
    #|      const incomingIds = new Set(file.notes.map(note => note.id));
    #|      const exact = note => JSON.stringify([note.start_ms, note.end_ms, note.text, note.resolved]);
    #|      const candidates = file.notes.filter(note => !current.has(note.id) || exact(note) !== exact(current.get(note.id))).map(note => ({before: current.has(note.id) ? {...current.get(note.id)} : null, after: {...note}, selected: false}));
    #|      const review = {name: file.name, revision, candidates, unchanged: file.notes.length - candidates.length, currentOnly: notes.filter(note => !incomingIds.has(note.id)).length};
    #|      pendingRevision = review; revisionPanel.hidden = false;
    #|      candidates.forEach(candidate => {
    #|        const row = document.createElement('li'), label = document.createElement('label'), choice = document.createElement('input');
    #|        choice.type = 'checkbox'; choice.checked = false;
    #|        label.appendChild(choice);
    #|        const title = document.createElement('span'); title.textContent = candidate.before ? ' Replace local issue #' + candidate.after.id + ' with this incoming version' : ' Add incoming issue #' + candidate.after.id + ' as a new local note'; label.appendChild(title); row.appendChild(label);
    #|        const before = document.createElement('p'); before.className = 'words';
    #|        before.textContent = candidate.before ? 'Current #' + candidate.before.id + ' · ' + spanLabel(candidate.before) + ' · ' + (candidate.before.resolved ? 'Resolved' : 'Open') + '\n' + candidate.before.text : 'Current: no note with this ID. This addition is not deduplicated by wording.';
    #|        const after = document.createElement('p'); after.className = 'words'; after.textContent = 'Incoming #' + candidate.after.id + ' · ' + spanLabel(candidate.after) + ' · ' + (candidate.after.resolved ? 'Resolved' : 'Open') + '\n' + candidate.after.text;
    #|        row.appendChild(before); row.appendChild(after); revisionList.appendChild(row);
    #|        choice.addEventListener('change', () => { if (pendingRevision !== review || review.revision !== revision) return; candidate.selected = choice.checked; showRevisionSelection(); });
    #|      });
    #|      showRevisionSelection();
    #|    });
    #|    document.getElementById('review-revision-cancel').addEventListener('click', clearRevision);
    #|    revisionApply.addEventListener('click', () => {
    #|      if (!pendingRevision || !pendingImport || pendingRevision.revision !== revision || pendingImport.revision !== revision) return;
    #|      const selected = revisionChoices(), additions = selected.filter(candidate => !candidate.before);
    #|      if (!selected.length || notes.length + additions.length > 500 || selected.some(candidate => candidate.before && candidate.before.id === editing)) { showRevisionSelection(); return; }
    #|      const replacements = new Map(selected.filter(candidate => candidate.before).map(candidate => [candidate.before.id, candidate.after]));
    #|      notes = notes.map(note => ({...(replacements.get(note.id) || note)})).concat(additions.map(candidate => ({...candidate.after})));
    #|      if (selectedIssue && replacements.has(selectedIssue.id)) selectedIssue = {id: selectedIssue.id, start_ms: replacements.get(selectedIssue.id).start_ms};
    #|      changed('Applied ' + replacements.size + ' reviewed replacements and ' + additions.length + ' additions. Other saved notes and editor draft kept. Download the notebook to keep these revisions.', 'Apply selected revisions');
    #|    });
    #|    function previewImport(loaded) {
    #|      const merge = mergeNotebooks(loaded);
    #|      pendingImport = {loaded, merge, revision};
    #|      noteApply.disabled = loaded.length !== 1; revisionOpen.disabled = loaded.length !== 1;
    #|      noteMerge.disabled = merge.additions.length === 0 || merge.notes.length > 500;
    #|      noteDiscard.disabled = false;
    #|      const replacement = loaded.length === 1 ? ' Replace current notebook will replace ' + notes.length + ' current notes and any uncommitted editor text. Download current notes first if you want both.' : ' Replacement is available only when selecting one notebook.';
    #|      noteImportStatus.textContent = loaded.length + ' matching notebook(s): ' + loaded.reduce((count, file) => count + file.notes.length, 0) + ' incoming notes. Merge preview: ' + merge.additions.length + ' additions, ' + merge.duplicates + ' exact duplicates skipped, ' + merge.variants + ' differing-status additions kept separately, ' + merge.conflicts.length + ' same-ID content conflicts. Merge keeps both distinct contents, assigning new local IDs to additions; ' + merge.notes.length + ' total notes. ' + (merge.notes.length > 500 ? 'Merge blocked: the combined notebook exceeds 500 notes. Select fewer notebooks or keep separate notebooks.' : merge.additions.length === 0 ? 'Nothing new to merge.' : 'Merge keeps current notes and uncommitted editor text.') + replacement;
    #|      loaded.forEach(file => {
    #|        const row = document.createElement('li'); row.textContent = 'Selected file: ' + file.name + ' · ' + file.notes.length + ' notes (filename is not reviewer identity).'; mergePreview.appendChild(row);
    #|      });
    #|      merge.conflicts.forEach(conflict => {
    #|        const row = document.createElement('li'); row.textContent = 'ID conflict: ' + conflict.file + ' #' + conflict.id + ' differs from ' + conflict.prior.join(', ') + '. ' + (conflict.duplicate ? 'This exact content already exists and is coalesced; both distinct contents remain.' : 'Keep both distinct contents; the incoming note receives a new local ID.'); mergePreview.appendChild(row);
    #|      });
    #|      merge.additions.slice(0, 500).forEach(addition => {
    #|        const row = document.createElement('li'); row.className = 'words';
    #|        row.textContent = 'Add as #' + addition.note.id + ' from ' + addition.file + ' (source #' + addition.sourceId + '): ' + spanLabel(addition.note) + ' · ' + (addition.note.resolved ? 'Resolved' : 'Open') + (addition.variant ? ' · Different status retained separately' : '') + '\n' + addition.note.text;
    #|        mergePreview.appendChild(row);
    #|      });
    #|      if (merge.additions.length > 500) { const row = document.createElement('li'); row.textContent = 'Only the first 500 proposed additions are shown. This over-capacity merge cannot be applied.'; mergePreview.appendChild(row); }
    #|    }
    #|    noteFile.addEventListener('change', async () => {
    #|      invalidateImport();
    #|      const epoch = importEpoch, sourceRevision = revision, files = Array.from(noteFile.files || []);
    #|      noteFile.value = '';
    #|      if (!files.length) { noteImportStatus.textContent = 'No notebook selected. Current notes are unchanged.'; return; }
    #|      if (files.length > 10) { noteImportStatus.textContent = 'Select at most 10 notebooks at a time. Current notes are unchanged.'; return; }
    #|      if (files.reduce((size, file) => size + file.size, 0) > 64 * 1024 * 1024) { noteImportStatus.textContent = 'Notebook selection exceeds 64 MiB. Current notes are unchanged.'; return; }
    #|      noteDiscard.disabled = false;
    #|      noteImportStatus.textContent = 'Reading notebooks; current notes are unchanged.';
    #|      try {
    #|        const loaded = [];
    #|        for (let index = 0; index < files.length; index += 1) {
    #|          const file = files[index], name = 'Notebook ' + (index + 1) + (file.name ? ' (' + file.name + ')' : '');
    #|          try {
    #|            const raw = await file.text();
    #|            if (epoch !== importEpoch || sourceRevision !== revision) return;
    #|            loaded.push({name, notes: validateNotebook(JSON.parse(raw))});
    #|          } catch (error) { throw Error(name + ': ' + error.message); }
    #|        }
    #|        previewImport(loaded);
    #|      } catch (error) { if (epoch === importEpoch) { invalidateImport(); noteImportStatus.textContent = 'Cannot load notebook selection: ' + error.message + ' Current notes are unchanged; no selected file was applied.'; } }
    #|    });
    #|    noteApply.addEventListener('click', () => {
    #|      if (!pendingImport || pendingImport.revision !== revision || pendingImport.loaded.length !== 1) return;
    #|      notes = pendingImport.loaded[0].notes; selectedIssue = null; resetEditor(); changed('Matching notebook loaded. Earlier notes were replaced only by this explicit action.', 'Replace notebook');
    #|    });
    #|    noteMerge.addEventListener('click', () => {
    #|      if (!pendingImport || pendingImport.revision !== revision || pendingImport.merge.notes.length > 500 || pendingImport.merge.additions.length === 0) return;
    #|      const added = pendingImport.merge.additions.length, duplicates = pendingImport.merge.duplicates;
    #|      notes = pendingImport.merge.notes;
    #|      changed('Merged ' + added + ' notes; skipped ' + duplicates + ' exact duplicates. Existing notes and editor draft kept. Download to keep the combined notebook.', 'Merge notebooks');
    #|    });
    #|    noteDiscard.addEventListener('click', () => { invalidateImport(); noteImportStatus.textContent = 'Loaded notebooks discarded. Current notes and editor draft are unchanged.'; });
    #|    clearRevision(); revisionOpen.disabled = true; showAnchor(); renderNotes();
    #|  }
    #|  document.querySelectorAll('[data-seek-ms]').forEach(button => {
    #|    button.addEventListener('click', () => seek(Number(button.dataset.seekMs)));
    #|  });
    #|  document.querySelectorAll('[data-nudge-ms]').forEach(button => {
    #|    button.addEventListener('click', () => seek((pendingSeek === null ? video.currentTime * 1000 : pendingSeek) + Number(button.dataset.nudgeMs)));
    #|  });
    #|  video.addEventListener('loadedmetadata', () => {
    #|    if (pendingSeek !== null) { const target = pendingSeek; pendingSeek = null; seek(target); }
    #|    update();
    #|  });
    #|  video.addEventListener('timeupdate', update);
    #|  video.addEventListener('seeked', update);
    #|  video.addEventListener('error', () => { status.textContent = 'This browser could not play media.mp4. Download it below and open it in a local H.264/AAC player; the transcript remains available.'; });
    #|  document.getElementById('speed').addEventListener('change', event => { video.playbackRate = Number(event.target.value); });
    #|  function filterCues() {
    #|    const query = search.value.trim().toLocaleLowerCase();
    #|    let visible = 0;
    #|    cueRows.forEach((row, index) => {
    #|      row.hidden = !displayedCaption(index).text.toLocaleLowerCase().includes(query);
    #|      if (!row.hidden) visible += 1;
    #|    });
    #|    count.textContent = visible + ' of ' + cueRows.length + ' cues';
    #|  }
    #|  search.addEventListener('input', filterCues);
    #|  if (captionsOn && typeof video.addTextTrack === 'function' && typeof VTTCue === 'function') {
    #|    try {
    #|      track = video.addTextTrack('captions', 'Screening captions', 'und');
    #|      captionCues.forEach(cue => { const item = new VTTCue(cue.start_ms / 1000, cue.end_ms / 1000, cue.text.replace(/&/g, '&amp;')); track.addCue(item); captionTrackCues.push(item); });
    #|      track.mode = 'showing';
    #|    } catch (_) { if (track) track.mode = 'disabled'; track = null; }
    #|  }
    #|  captionButton.addEventListener('click', () => {
    #|    captionsOn = !captionsOn;
    #|    captionButton.setAttribute('aria-pressed', String(captionsOn));
    #|    captionButton.textContent = captionsOn ? 'Captions on' : 'Captions off';
    #|    if (track) track.mode = captionsOn ? 'showing' : 'disabled';
    #|    update();
    #|  });
    #|  // Authored playback chapters have their own millisecond session clock. Never
    #|  // infer native timeline IDs/ticks or change the supplied plan/notebook context.
    #|  const authoredList = document.getElementById('chapter-author-list');
    #|  if (authoredList) {
    #|    const chapterStatus = document.getElementById('chapter-author-status');
    #|    const chapterPanel = document.getElementById('chapter-author-editor');
    #|    const chapterTitle = document.getElementById('chapter-author-label');
    #|    const chapterStart = document.getElementById('chapter-author-start');
    #|    const chapterCapture = document.getElementById('chapter-author-capture');
    #|    const chapterRecapture = document.getElementById('chapter-author-recapture');
    #|    const chapterPreviewButton = document.getElementById('chapter-author-preview');
    #|    const chapterApply = document.getElementById('chapter-author-apply');
    #|    const chapterCancel = document.getElementById('chapter-author-cancel');
    #|    const chapterDownload = document.getElementById('chapter-author-download');
    #|    const chapterPreviewStatus = document.getElementById('chapter-author-preview-status');
    #|    let authored = [], selectedMarker = null, chapterEditing = false, chapterPreview = null, chapterURL = null, chapterMediaError = false;
    #|    let authoredRows = [];
    #|    const supportedDuration = Number.isSafeInteger(data.duration_ms) && data.duration_ms > 0 && data.duration_ms <= 7200000;
    #|    function chapterClock(ms) { return clock(ms) + '.' + String(ms % 1000).padStart(3, '0'); }
    #|    function chapterKey() { return JSON.stringify([chapterStart.value, chapterTitle.value]); }
    #|    function chapterPreviewMatches() { return chapterPreview !== null && chapterPreview.key === chapterKey(); }
    #|    function chapterTitleError(title) {
    #|      if (!title.trim() || title.length > 200 || /[\x00-\x1f\x7f\u2028\u2029]/.test(title)) return 'Use a nonblank single-line chapter label of at most 200 UTF-16 units.';
    #|      if (Array.from(title).some(character => character.length === 1 && /[\ud800-\udfff]/.test(character))) return 'Use valid Unicode in the chapter label.';
    #|      if (title.endsWith('\\')) return 'A chapter label cannot end in a backslash in this FFmetadata profile.';
    #|      return '';
    #|    }
    #|    function validateChapters(markers) {
    #|      if (!supportedDuration || markers.length < 1 || markers.length > 1000) throw Error('Use 1–1000 chapter markers within a supported screening of at most two hours.');
    #|      let previous = -1;
    #|      markers.forEach(marker => {
    #|        if (!Number.isSafeInteger(marker.start_ms) || marker.start_ms <= previous || marker.start_ms >= data.duration_ms) throw Error('Chapter starts must be distinct whole milliseconds from 0 through ' + (data.duration_ms - 1) + '.');
    #|        const error = chapterTitleError(marker.title); if (error) throw Error(error);
    #|        previous = marker.start_ms;
    #|      });
    #|      return markers;
    #|    }
    #|    function chapterCandidate() {
    #|      if (!chapterEditing || !/^[0-9]+$/.test(chapterStart.value)) throw Error('Enter the chapter start as whole nonnegative milliseconds.');
    #|      const marker = {start_ms: Number(chapterStart.value), title: chapterTitle.value};
    #|      const markers = authored.filter(item => item !== selectedMarker).concat([marker]).sort((a, b) => a.start_ms - b.start_ms);
    #|      return validateChapters(markers);
    #|    }
    #|    function updateAuthoredCurrent() {
    #|      // Compare in the same seconds clock used for seeks: converting an exact
    #|      // 1.001 s back to floored milliseconds can incorrectly yield 1000.
    #|      const seconds = video.currentTime;
    #|      authoredRows.forEach(({row, start, end}) => {
    #|        const current = start / 1000 <= seconds && seconds < end / 1000;
    #|        row.classList.toggle('current', current);
    #|        if (current) row.setAttribute('aria-current', 'true'); else row.removeAttribute('aria-current');
    #|      });
    #|    }
    #|    function chapterPositionAvailable() {
    #|      return supportedDuration && !chapterMediaError && !video.error && video.readyState > 0 && !video.seeking && pendingSeek === null && Number.isFinite(video.duration) && video.duration > 0;
    #|    }
    #|    function previewChapterStart(start) {
    #|      if (!chapterPositionAvailable() || start >= mediaEnd()) { showChapterAuthor('Load a playable video and finish seeking before previewing this marker. Authored chapters and editor values are kept.'); return; }
    #|      seek(start);
    #|      updateAuthoredCurrent();
    #|      if (Math.abs(video.currentTime * 1000 - start) > 0.51) { showChapterAuthor('Could not reach the marker. Authored chapters and editor values are kept.'); return; }
    #|      showChapterAuthor('Preview position ' + chapterClock(start) + '. Seeking never starts playback.');
    #|    }
    #|    function renderAuthored() {
    #|      authoredList.replaceChildren(); authoredRows = [];
    #|      const markers = chapterPreviewMatches() ? chapterPreview.markers : authored;
    #|      markers.forEach((marker, index) => {
    #|        const end = index + 1 < markers.length ? markers[index + 1].start_ms : data.duration_ms;
    #|        const row = document.createElement('li');
    #|        const preview = document.createElement('button'); preview.type = 'button';
    #|        preview.textContent = 'Preview ' + chapterClock(marker.start_ms) + '–' + chapterClock(end) + ' · ' + marker.title;
    #|        preview.addEventListener('click', () => previewChapterStart(marker.start_ms)); row.appendChild(preview);
    #|        const controls = document.createElement('div'); controls.setAttribute('class', 'controls');
    #|        const edit = document.createElement('button'); edit.type = 'button'; edit.textContent = 'Edit marker ' + (index + 1); edit.disabled = chapterEditing;
    #|        edit.addEventListener('click', () => {
    #|          if (chapterEditing || !authored.includes(marker)) { showChapterAuthor('Apply or cancel the current marker before editing another.'); return; }
    #|          chapterEditing = true; selectedMarker = marker; chapterStart.value = String(marker.start_ms); chapterTitle.value = marker.title;
    #|          renderAuthored(); showChapterAuthor('Edit the label or start, then preview and apply. Cancel keeps the saved marker.'); chapterTitle.focus();
    #|        });
    #|        const remove = document.createElement('button'); remove.type = 'button'; remove.textContent = 'Remove marker ' + (index + 1); remove.disabled = chapterEditing;
    #|        remove.addEventListener('click', () => {
    #|          if (chapterEditing) { showChapterAuthor('Apply or cancel the current marker before removing a marker.'); return; }
    #|          authored = authored.filter(item => item !== marker); renderAuthored(); showChapterAuthor('Marker removed from this session. Remaining intervals now end at the next marker or screening duration. Download to keep your work.');
    #|        });
    #|        controls.appendChild(edit); controls.appendChild(remove); row.appendChild(controls); authoredList.appendChild(row);
    #|        authoredRows.push({row, start: marker.start_ms, end});
    #|      });
    #|      updateAuthoredCurrent();
    #|    }
    #|    function showChapterAuthor(message = '') {
    #|      chapterCapture.disabled = !supportedDuration || chapterEditing || authored.length >= 1000;
    #|      chapterPanel.hidden = !chapterEditing;
    #|      [chapterStart, chapterTitle, chapterRecapture, chapterPreviewButton, chapterCancel].forEach(control => { control.disabled = !chapterEditing; });
    #|      chapterApply.disabled = !chapterEditing || !chapterPreviewMatches();
    #|      chapterDownload.disabled = !supportedDuration || !authored.length || chapterEditing;
    #|      chapterPreviewStatus.hidden = !chapterPreviewMatches();
    #|      chapterPreviewStatus.textContent = chapterPreviewMatches() ? 'Unsaved preview: ' + chapterPreview.markers.length + ' marker(s), contiguous intervals, final end ' + data.duration_ms + ' ms. Apply marker to keep this version, or Cancel edit.' : '';
    #|      chapterStatus.textContent = (message ? message + ' ' : '') + authored.length + ' session marker(s). Supplied chapters and notebook context remain unchanged. Download FFmetadata before closing; this page does not save automatically.';
    #|    }
    #|    function captureChapterPosition(recapture) {
    #|      if ((!recapture && chapterEditing) || (recapture && !chapterEditing)) { showChapterAuthor('Apply or cancel the current marker before capturing another.'); return; }
    #|      const position = Math.round(video.currentTime * 1000);
    #|      if (!chapterPositionAvailable() || !Number.isFinite(video.currentTime) || video.currentTime < 0 || video.currentTime * 1000 >= mediaEnd() || !Number.isSafeInteger(position) || position < 0 || position >= Math.min(data.duration_ms, mediaEnd())) {
    #|        showChapterAuthor('Load the video and choose a stable position before its end to capture a chapter start. Editor values are kept.'); return;
    #|      }
    #|      if (authored.some(marker => marker !== selectedMarker && marker.start_ms === position)) { showChapterAuthor('A marker already starts at ' + position + ' ms. Edit that marker or choose another position.'); return; }
    #|      if (!recapture && authored.length >= 1000) { showChapterAuthor('The session already has 1000 markers. Remove one before adding another.'); return; }
    #|      chapterPreview = null; chapterEditing = true; chapterStart.value = String(position);
    #|      if (!recapture) { selectedMarker = null; chapterTitle.value = ''; }
    #|      renderAuthored(); showChapterAuthor('Captured ' + position + ' ms. Label the marker, preview the resulting intervals, then apply.'); chapterTitle.focus();
    #|    }
    #|    chapterCapture.addEventListener('click', () => captureChapterPosition(false));
    #|    chapterRecapture.addEventListener('click', () => captureChapterPosition(true));
    #|    [chapterStart, chapterTitle].forEach(control => control.addEventListener('input', () => { chapterPreview = null; renderAuthored(); showChapterAuthor('Editor changed. Preview again before applying.'); }));
    #|    chapterPreviewButton.addEventListener('click', () => {
    #|      if (!chapterEditing) return;
    #|      chapterPreview = null;
    #|      try { chapterPreview = {markers: chapterCandidate(), key: chapterKey()}; renderAuthored(); showChapterAuthor('Previewing unsaved chapter intervals below. Use a Preview row to seek.'); }
    #|      catch (error) { renderAuthored(); showChapterAuthor(error.message); }
    #|    });
    #|    chapterApply.addEventListener('click', () => {
    #|      if (!chapterEditing) return;
    #|      if (!chapterPreviewMatches()) { chapterPreview = null; renderAuthored(); showChapterAuthor('Preview the current marker before applying it.'); return; }
    #|      try { authored = chapterCandidate(); }
    #|      catch (error) { chapterPreview = null; renderAuthored(); showChapterAuthor(error.message); return; }
    #|      chapterEditing = false; selectedMarker = null; chapterPreview = null; chapterStart.value = chapterTitle.value = '';
    #|      renderAuthored(); showChapterAuthor('Marker applied for this session. Download to keep the authored chapters.'); chapterCapture.focus();
    #|    });
    #|    chapterCancel.addEventListener('click', () => {
    #|      chapterEditing = false; selectedMarker = null; chapterPreview = null; chapterStart.value = chapterTitle.value = '';
    #|      renderAuthored(); showChapterAuthor('Editor closed. Applied markers are unchanged.'); chapterCapture.focus();
    #|    });
    #|    chapterDownload.addEventListener('click', () => {
    #|      if (chapterEditing) { showChapterAuthor('Download blocked; apply or cancel the current marker first.'); return; }
    #|      let link = null;
    #|      try {
    #|        validateChapters(authored);
    #|        const escapeTitle = title => title.replace(/[\\=;#]/g, character => '\\' + character);
    #|        const text = ';FFMETADATA1\n' + authored.map((marker, index) => '[CHAPTER]\nTIMEBASE=1/1000\nSTART=' + marker.start_ms + '\nEND=' + (index + 1 < authored.length ? authored[index + 1].start_ms : data.duration_ms) + '\ntitle=' + escapeTitle(marker.title) + '\n').join('');
    #|        const blob = new Blob([text], {type: 'text/plain;charset=utf-8'});
    #|        if (blob.size > 2097152) throw Error('Chapter sidecar exceeds 2 MiB.');
    #|        if (chapterURL) URL.revokeObjectURL(chapterURL);
    #|        chapterURL = URL.createObjectURL(blob); link = document.createElement('a'); link.href = chapterURL; link.download = 'screening-authored-chapters.ffmetadata';
    #|        document.body.appendChild(link); link.click();
    #|        showChapterAuthor('FFmetadata download requested. Check that your browser saved it. Import into a separately selected matching-cut draft only when every millisecond boundary lands exactly on its native tick clock.');
    #|      } catch (error) { showChapterAuthor('Could not download chapters: ' + error.message + ' Session markers are kept.'); }
    #|      finally { if (link) link.remove(); }
    #|    });
    #|    video.addEventListener('timeupdate', updateAuthoredCurrent);
    #|    video.addEventListener('seeked', updateAuthoredCurrent);
    #|    video.addEventListener('error', () => { chapterMediaError = true; showChapterAuthor('Video playback failed. Chapter markers and editor values are kept; saved markers can still be downloaded.'); });
    #|    video.addEventListener('loadedmetadata', () => { chapterMediaError = Boolean(video.error); updateAuthoredCurrent(); });
    #|    renderAuthored(); showChapterAuthor();
    #|  }
    #|  // Caption wording and timing are a separate session draft. Never mutate the embedded
    #|  // screening plan: notebook source identity and supplied context stay exact.
    #|  const captionEditor = document.getElementById('caption-edit-text');
    #|  if (captionEditor) {
    #|    const captionStatus = document.getElementById('caption-edit-status');
    #|    const captionAnchor = document.getElementById('caption-edit-anchor');
    #|    const captionSave = document.getElementById('caption-edit-save');
    #|    const captionCancel = document.getElementById('caption-edit-cancel');
    #|    const captionRestore = document.getElementById('caption-edit-restore');
    #|    const captionStart = document.getElementById('caption-edit-start');
    #|    const captionEnd = document.getElementById('caption-edit-end');
    #|    const captionCaptureStart = document.getElementById('caption-capture-start');
    #|    const captionCaptureEnd = document.getElementById('caption-capture-end');
    #|    const captionRestoreTiming = document.getElementById('caption-restore-timing');
    #|    const captionPreviewButton = document.getElementById('caption-preview');
    #|    const captionPreviewStatus = document.getElementById('caption-preview-status');
    #|    const captionJson = document.getElementById('caption-download-json');
    #|    const captionVtt = document.getElementById('caption-download-vtt');
    #|    const editButtons = Array.from(document.querySelectorAll('[data-caption-edit-index]'));
    #|    let selectedCaption = null, captionURL = null;
    #|    function timingDirty() { return selectedCaption !== null && (captionStart.value !== String(captionCues[selectedCaption].start_ms) || captionEnd.value !== String(captionCues[selectedCaption].end_ms)); }
    #|    function captionDirty() { return selectedCaption !== null && (timingDirty() || captionEditor.value !== captionCues[selectedCaption].text); }
    #|    function editorKey() { return JSON.stringify([selectedCaption, captionStart.value, captionEnd.value, captionEditor.value]); }
    #|    function previewMatches() { return captionPreview !== null && captionPreview.key === editorKey(); }
    #|    function captionClock(ms) { return clock(ms) + '.' + String(ms % 1000).padStart(3, '0'); }
    #|    function cueChanged(cue, original) { return cue.text !== original.text || cue.start_ms !== original.start_ms || cue.end_ms !== original.end_ms; }
    #|    function showCaptionEditor(message = '') {
    #|      const changed = captionCues.filter((cue, index) => cueChanged(cue, data.cues[index])).length;
    #|      const dirty = captionDirty();
    #|      [captionEditor, captionStart, captionEnd, captionCaptureStart, captionCaptureEnd, captionRestoreTiming].forEach(control => { control.disabled = selectedCaption === null; });
    #|      captionSave.disabled = !dirty || (timingDirty() && !previewMatches());
    #|      captionPreviewButton.disabled = !dirty;
    #|      captionCancel.disabled = selectedCaption === null;
    #|      captionRestore.disabled = selectedCaption === null;
    #|      captionJson.disabled = captionVtt.disabled = !captionCues.length || dirty;
    #|      captionAnchor.textContent = selectedCaption === null ? 'Choose Edit caption beside a transcript cue.' : 'Editing caption ' + (selectedCaption + 1) + ' of ' + captionCues.length + ': ' + captionClock(captionCues[selectedCaption].start_ms) + '–' + captionClock(captionCues[selectedCaption].end_ms) + '. Applied session timing. Enter whole milliseconds; preview timing before applying.';
    #|      captionPreviewStatus.hidden = captionPreview === null;
    #|      captionPreviewStatus.textContent = captionPreview === null ? '' : 'Preview only for caption ' + (captionPreview.index + 1) + ': ' + captionClock(captionCues[captionPreview.index].start_ms) + '–' + captionClock(captionCues[captionPreview.index].end_ms) + ' → ' + captionClock(captionPreview.cue.start_ms) + '–' + captionClock(captionPreview.cue.end_ms) + '. Transcript, seek buttons and captions show this unsaved preview. Apply correction to keep it for this session, or Cancel edit to restore the applied version.';
    #|      captionStatus.textContent = (message ? message + ' ' : '') + changed + ' of ' + captionCues.length + ' captions corrected in this session. ' + (dirty ? 'Unsaved correction: preview timing, then apply or cancel before switching captions or downloading.' : 'Download corrected captions to keep applied corrections before closing. Original files are unchanged.');
    #|    }
    #|    function captionTextError(text) {
    #|      if (!text.trim() || text.length > 2000 || /[<>]/.test(text)) return 'Use 1–2000 characters of plain text without angle brackets.';
    #|      if (text.split('\n').some(line => !line.trim())) return 'Blank caption lines are not supported; use one newline between nonblank lines.';
    #|      if (/[\x00-\x09\x0b-\x1f]/.test(text)) return 'Control characters, including tabs and carriage returns, are not supported.';
    #|      return '';
    #|    }
    #|    function editorCue() {
    #|      if (!/^\d+$/.test(captionStart.value) || !/^\d+$/.test(captionEnd.value)) throw Error('Enter start and end as whole, nonnegative milliseconds.');
    #|      const cue = {start_ms: Number(captionStart.value), end_ms: Number(captionEnd.value), text: captionEditor.value};
    #|      if (!Number.isSafeInteger(cue.start_ms) || !Number.isSafeInteger(cue.end_ms) || cue.start_ms >= cue.end_ms || cue.end_ms > data.duration_ms) throw Error('Start must precede end, and both must be inside the screening duration of ' + data.duration_ms + ' ms.');
    #|      if ((selectedCaption > 0 && cue.start_ms < captionCues[selectedCaption - 1].start_ms) || (selectedCaption + 1 < captionCues.length && cue.start_ms > captionCues[selectedCaption + 1].start_ms)) throw Error('Keep cue starts in their existing order. Equal starts and overlapping ends are allowed; cues are never silently sorted.');
    #|      const error = captionTextError(cue.text); if (error) throw Error(error);
    #|      return cue;
    #|    }
    #|    function syncCaptionPresentation(index) {
    #|      const cue = displayedCaption(index), row = cueRows[index];
    #|      const words = row && row.querySelector('.words'), time = row && row.querySelector('.time'), seekButton = row && row.querySelector('[data-seek-ms]');
    #|      if (words) words.textContent = cue.text;
    #|      if (time) time.textContent = captionClock(cue.start_ms) + '–' + captionClock(cue.end_ms);
    #|      if (seekButton) { seekButton.dataset.seekMs = String(cue.start_ms); seekButton.setAttribute('data-seek-ms', String(cue.start_ms)); }
    #|      const button = editButtons.find(item => Number(item.dataset.captionEditIndex) === index);
    #|      if (button) button.textContent = 'Edit caption ' + (index + 1) + (captionPreview && captionPreview.index === index ? ' (preview)' : cueChanged(cue, data.cues[index]) ? ' (corrected)' : '');
    #|      if (track) {
    #|        try {
    #|          const item = captionTrackCues[index];
    #|          // Move the safe endpoint first, including edits completely past the old interval.
    #|          if (cue.start_ms / 1000 >= item.endTime) { item.endTime = cue.end_ms / 1000; item.startTime = cue.start_ms / 1000; }
    #|          else { item.startTime = cue.start_ms / 1000; item.endTime = cue.end_ms / 1000; }
    #|          item.text = cue.text.replace(/&/g, '&amp;');
    #|        } catch (_) { try { track.mode = 'disabled'; } catch (_) {} track = null; }
    #|      }
    #|      filterCues(); update();
    #|    }
    #|    function clearCaptionPreview() {
    #|      if (!captionPreview) return;
    #|      const index = captionPreview.index; captionPreview = null; syncCaptionPresentation(index);
    #|    }
    #|    function discardStalePreview() { if (captionPreview && !previewMatches()) clearCaptionPreview(); }
    #|    editButtons.forEach(button => button.addEventListener('click', () => {
    #|      const index = Number(button.dataset.captionEditIndex);
    #|      if (!Number.isInteger(index) || index < 0 || index >= captionCues.length) return;
    #|      discardStalePreview();
    #|      if (captionDirty()) { showCaptionEditor('Current correction was kept.'); return; }
    #|      clearCaptionPreview(); selectedCaption = index;
    #|      captionEditor.value = captionCues[index].text; captionStart.value = String(captionCues[index].start_ms); captionEnd.value = String(captionCues[index].end_ms);
    #|      showCaptionEditor(); captionEditor.focus();
    #|    }));
    #|    [captionEditor, captionStart, captionEnd].forEach(control => control.addEventListener('input', () => { clearCaptionPreview(); showCaptionEditor(); }));
    #|    captionCancel.addEventListener('click', () => {
    #|      clearCaptionPreview(); selectedCaption = null; captionEditor.value = ''; captionStart.value = ''; captionEnd.value = '';
    #|      showCaptionEditor('Editor closed; previously applied corrections kept.');
    #|    });
    #|    captionRestore.addEventListener('click', () => {
    #|      if (selectedCaption === null) return;
    #|      clearCaptionPreview(); captionEditor.value = data.cues[selectedCaption].text;
    #|      showCaptionEditor('Supplied wording is in the editor. Apply to keep it, or cancel to keep the applied correction.');
    #|    });
    #|    captionRestoreTiming.addEventListener('click', () => {
    #|      if (selectedCaption === null) return;
    #|      clearCaptionPreview(); captionStart.value = String(data.cues[selectedCaption].start_ms); captionEnd.value = String(data.cues[selectedCaption].end_ms);
    #|      showCaptionEditor('Supplied timing is in the editor. Preview and apply it, or cancel to keep the applied correction. Neighboring applied starts still constrain this restoration.');
    #|    });
    #|    function captureCaptionPosition(control) {
    #|      if (selectedCaption === null) return;
    #|      const position = Math.round(video.currentTime * 1000);
    #|      if (video.readyState === 0 || !Number.isFinite(video.currentTime) || video.currentTime < 0 || position > Math.floor(mediaEnd())) { showCaptionEditor('Load the video and choose a position inside its duration before capturing timing. Editor values are kept.'); return; }
    #|      clearCaptionPreview(); control.value = String(position);
    #|      showCaptionEditor('Captured ' + position + ' ms in the selected caption draft. Preview to validate the complete interval.');
    #|    }
    #|    captionCaptureStart.addEventListener('click', () => captureCaptionPosition(captionStart));
    #|    captionCaptureEnd.addEventListener('click', () => captureCaptionPosition(captionEnd));
    #|    captionPreviewButton.addEventListener('click', () => {
    #|      if (selectedCaption === null || !captionDirty()) { clearCaptionPreview(); showCaptionEditor(); return; }
    #|      clearCaptionPreview();
    #|      try { captionPreview = {index: selectedCaption, cue: editorCue(), key: editorKey()}; syncCaptionPresentation(selectedCaption); showCaptionEditor('Unsaved correction is previewing. Playback position, speed and repeat are unchanged.'); }
    #|      catch (error) { showCaptionEditor(error.message); }
    #|    });
    #|    captionSave.addEventListener('click', () => {
    #|      discardStalePreview();
    #|      if (selectedCaption === null || !captionDirty()) { showCaptionEditor(); return; }
    #|      let cue;
    #|      try { cue = editorCue(); } catch (error) { showCaptionEditor(error.message); return; }
    #|      if (timingDirty() && !previewMatches()) { showCaptionEditor('Preview the timing correction before applying it.'); return; }
    #|      const index = selectedCaption;
    #|      captionPreview = null; captionCues[index] = cue;
    #|      captionStart.value = String(cue.start_ms); captionEnd.value = String(cue.end_ms);
    #|      syncCaptionPresentation(index); showCaptionEditor('Correction applied for this session in the transcript and captions. Download to keep it.');
    #|    });
    #|    const bulkFind = document.getElementById('caption-replace-find');
    #|    const bulkWith = document.getElementById('caption-replace-with');
    #|    const bulkStatus = document.getElementById('caption-replace-status');
    #|    const bulkList = document.getElementById('caption-replace-list');
    #|    const bulkApply = document.getElementById('caption-replace-apply');
    #|    let replacement = null;
    #|    function resetReplacement() { replacement = null; bulkApply.disabled = true; bulkList.replaceChildren(); }
    #|    [bulkFind, bulkWith].forEach(control => control.addEventListener('input', () => { resetReplacement(); bulkStatus.textContent = 'Replacement changed. Preview again before applying.'; }));
    #|    document.getElementById('caption-replace-preview').addEventListener('click', () => {
    #|      resetReplacement();
    #|      if (captionDirty() || captionPreview) { bulkStatus.textContent = 'Apply or cancel the single-caption edit first.'; return; }
    #|      const needle = bulkFind.value, value = bulkWith.value;
    #|      if (!needle || needle.length > 2000 || value.length > 2000) { bulkStatus.textContent = 'Enter a nonempty literal search, up to 2000 characters per field.'; return; }
    #|      const changes = [];
    #|      for (let index = 0; index < captionCues.length; index++) {
    #|        const before = captionCues[index].text, after = before.split(needle).join(value);
    #|        if (after === before) continue;
    #|        const error = captionTextError(after);
    #|        if (error) { bulkStatus.textContent = 'Caption ' + (index + 1) + ': ' + error + ' Nothing changed.'; return; }
    #|        changes.push({index, before, after});
    #|      }
    #|      changes.forEach(change => { const row = document.createElement('li'); row.textContent = 'Caption ' + (change.index + 1) + ': ' + change.before + ' → ' + change.after; bulkList.appendChild(row); });
    #|      replacement = {source: JSON.stringify(captionCues), needle, value, changes};
    #|      bulkApply.disabled = !changes.length;
    #|      bulkStatus.textContent = changes.length + ' captions would change. Case-sensitive literal replacement across all applied captions, including hidden search results. Timings stay unchanged. Review every change below.';
    #|    });
    #|    bulkApply.addEventListener('click', () => {
    #|      if (!replacement) return;
    #|      if (captionDirty() || captionPreview || replacement.source !== JSON.stringify(captionCues) || replacement.needle !== bulkFind.value || replacement.value !== bulkWith.value) { resetReplacement(); bulkStatus.textContent = 'Caption edits or replacement inputs changed. Preview again; nothing applied.'; return; }
    #|      const changes = replacement.changes;
    #|      changes.forEach(change => { captionCues[change.index] = {...captionCues[change.index], text: change.after}; });
    #|      if (selectedCaption !== null) captionEditor.value = captionCues[selectedCaption].text;
    #|      changes.forEach(change => syncCaptionPresentation(change.index));
    #|      resetReplacement(); showCaptionEditor();
    #|      bulkStatus.textContent = changes.length + ' caption corrections applied for this session. Download corrected captions to keep them. Original files are unchanged.';
    #|    });
    #|    function correctedCaptionDraft() {
    #|      if (!captionCues.length || captionCues.length > 5000 || !Number.isInteger(data.duration_ms) || data.duration_ms < 1 || data.duration_ms > 7200000) throw Error('The screening has no supported caption draft.');
    #|      let previous = -1;
    #|      captionCues.forEach(cue => {
    #|        if (!Number.isInteger(cue.start_ms) || !Number.isInteger(cue.end_ms) || cue.start_ms < 0 || cue.start_ms < previous || cue.end_ms <= cue.start_ms || cue.end_ms > data.duration_ms) throw Error('Caption timing is outside the supported draft.');
    #|        const error = captionTextError(cue.text); if (error) throw Error(error);
    #|        previous = cue.start_ms;
    #|      });
    #|      const digest = document.getElementById('screening-source-sha256').textContent;
    #|      if (!/^[a-f0-9]{64}$/.test(digest)) throw Error('The recorded media identity is unavailable.');
    #|      return {contract: 'mooncast.caption-draft.v1', source_file: 'screening media.mp4; recorded SHA-256: ' + digest, duration_ms: data.duration_ms, cues: captionCues.map(cue => ({start_ms: cue.start_ms, end_ms: cue.end_ms, text: cue.text}))};
    #|    }
    #|    const resumeFile = document.getElementById('caption-resume-file');
    #|    const resumeApply = document.getElementById('caption-resume-apply');
    #|    const resumeStatus = document.getElementById('caption-resume-status');
    #|    const resumeList = document.getElementById('caption-resume-list');
    #|    let resumeEpoch = 0, resumed = null;
    #|    function resetResume() { resumeEpoch++; resumed = null; resumeApply.disabled = true; resumeList.replaceChildren(); }
    #|    function importedCaptionDraft(text) {
    #|      const expected = correctedCaptionDraft(), loaded = JSON.parse(text);
    #|      if (!loaded || loaded.contract !== expected.contract || loaded.source_file !== expected.source_file || loaded.duration_ms !== expected.duration_ms) throw Error('Use a corrected-caption JSON downloaded from this recorded media SHA-256 and screening duration.');
    #|      if (!Array.isArray(loaded.cues) || loaded.cues.length !== captionCues.length) throw Error('The saved draft must have the same cue count. This player resumes wording and timing; it cannot add or remove cues.');
    #|      let previous = -1;
    #|      return loaded.cues.map((cue, index) => {
    #|        if (!cue || !Number.isSafeInteger(cue.start_ms) || !Number.isSafeInteger(cue.end_ms) || cue.start_ms < 0 || cue.start_ms < previous || cue.end_ms <= cue.start_ms || cue.end_ms > data.duration_ms) throw Error('Caption ' + (index + 1) + ' has invalid timing or out-of-order starts.');
    #|        if (typeof cue.text !== 'string') throw Error('Caption ' + (index + 1) + ' needs plain-text wording.');
    #|        const error = captionTextError(cue.text); if (error) throw Error('Caption ' + (index + 1) + ': ' + error);
    #|        previous = cue.start_ms;
    #|        return {start_ms: cue.start_ms, end_ms: cue.end_ms, text: cue.text};
    #|      });
    #|    }
    #|    resumeFile.addEventListener('change', async () => {
    #|      resetResume(); const epoch = resumeEpoch, file = resumeFile.files && resumeFile.files[0];
    #|      if (!file) { resumeStatus.textContent = 'No saved draft selected. Applied captions are kept.'; return; }
    #|      if (captionDirty() || captionPreview) { resumeStatus.textContent = 'Apply or cancel the single-caption edit, then select the saved file again.'; return; }
    #|      const source = JSON.stringify(captionCues);
    #|      resumeStatus.textContent = 'Reading saved caption draft…';
    #|      try {
    #|        if (!Number.isFinite(file.size) || file.size < 0 || file.size > 16777216) throw Error('Choose a corrected-caption JSON up to 16 MiB.');
    #|        const text = await file.text();
    #|        if (epoch !== resumeEpoch) return;
    #|        if (new Blob([text]).size > 16777216) throw Error('Saved caption draft exceeds 16 MiB.');
    #|        if (captionDirty() || captionPreview || source !== JSON.stringify(captionCues)) throw Error('Captions changed during file reading. Select the file again.');
    #|        const cues = importedCaptionDraft(text), changed = [];
    #|        cues.forEach((cue, index) => { if (cueChanged(cue, captionCues[index])) changed.push(index); });
    #|        changed.forEach(index => {
    #|          const before = captionCues[index], after = cues[index], row = document.createElement('li');
    #|          row.textContent = 'Caption ' + (index + 1) + ': ' + captionClock(before.start_ms) + '–' + captionClock(before.end_ms) + ' ' + before.text + ' → ' + captionClock(after.start_ms) + '–' + captionClock(after.end_ms) + ' ' + after.text;
    #|          resumeList.appendChild(row);
    #|        });
    #|        resumed = {source, cues, changed}; resumeApply.disabled = !changed.length;
    #|        resumeStatus.textContent = changed.length + ' of ' + cues.length + ' captions differ. Review the complete before/after list, then replace the applied caption draft. Download current corrections first if you need a recovery copy. No captions changed yet.';
    #|      } catch (error) { if (epoch === resumeEpoch) { resetResume(); resumeStatus.textContent = 'Could not reopen captions: ' + error.message + ' Applied captions are kept.'; } }
    #|    });
    #|    resumeApply.addEventListener('click', () => {
    #|      if (!resumed || !resumed.changed.length) return;
    #|      if (captionDirty() || captionPreview || resumed.source !== JSON.stringify(captionCues)) { resetResume(); resumeStatus.textContent = 'Caption edits changed after preview. Select the file again; nothing applied.'; return; }
    #|      const loaded = resumed, count = loaded.changed.length;
    #|      loaded.cues.forEach((cue, index) => { captionCues[index] = {...cue}; });
    #|      if (selectedCaption !== null) { const cue = captionCues[selectedCaption]; captionEditor.value = cue.text; captionStart.value = String(cue.start_ms); captionEnd.value = String(cue.end_ms); }
    #|      loaded.changed.forEach(index => syncCaptionPresentation(index));
    #|      resetResume(); resetReplacement(); showCaptionEditor();
    #|      resumeStatus.textContent = 'Reopened ' + count + ' changed captions for this session. Continue editing and download again before closing. Original screening and feedback context are unchanged.';
    #|    });
    #|    document.getElementById('caption-resume-cancel').addEventListener('click', () => { resetResume(); resumeFile.value = ''; resumeStatus.textContent = 'Saved draft preview dismissed. Applied captions are kept.'; });
    #|    function downloadCaptions(format) {
    #|      discardStalePreview();
    #|      if (captionDirty()) { showCaptionEditor('Download blocked; apply or cancel the current correction first.'); return; }
    #|      let link = null;
    #|      try {
    #|        const draft = correctedCaptionDraft();
    #|        const text = format === 'json' ? JSON.stringify(draft, null, 2) + '\n' : 'WEBVTT\n\n' + draft.cues.map((cue, index) => (index + 1) + '\n' + captionClock(cue.start_ms) + ' --> ' + captionClock(cue.end_ms) + '\n' + cue.text.replace(/&/g, '&amp;') + '\n').join('\n');
    #|        const blob = new Blob([text], {type: format === 'json' ? 'application/json;charset=utf-8' : 'text/vtt;charset=utf-8'});
    #|        if (blob.size > (format === 'json' ? 16777216 : 2097152)) throw Error('Corrected export exceeds the ' + (format === 'json' ? '16' : '2') + ' MiB limit; shorten captions or use separate drafts.');
    #|        if (captionURL) URL.revokeObjectURL(captionURL);
    #|        captionURL = URL.createObjectURL(blob);
    #|        link = document.createElement('a'); link.href = captionURL; link.download = 'screening-corrected-captions.' + format;
    #|        document.body.appendChild(link); link.click();
    #|        showCaptionEditor('Corrected ' + format.toUpperCase() + ' download requested. Check that your browser saved it; downloading does not approve or import it.');
    #|      } catch (error) { showCaptionEditor('Could not download corrected captions: ' + error.message + ' Applied corrections and editor values are kept.'); }
    #|      finally { if (link) link.remove(); }
    #|    }
    #|    captionJson.addEventListener('click', () => downloadCaptions('json'));
    #|    captionVtt.addEventListener('click', () => downloadCaptions('vtt'));
    #|    showCaptionEditor();
    #|  }
    #|  update();
    #|})();
  script
}

///|
/// A standalone player: no fetch, external scripts, analytics or server required.
pub fn Plan::html(
  self : Plan,
  source_name : String,
  source_sha256 : String,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>" +
    escape_html(self.title) +
    "</title><style>",
  )
  out.write_string(
    "body{margin:0;background:#f3f4f1;color:#172326;font:16px/1.5 system-ui,sans-serif}header,main,footer{max-width:1180px;margin:auto;padding:1.2rem}h1{margin:.2rem 0}a{color:#005c77}button,input,select,textarea{font:inherit}textarea{width:95%;max-width:50rem;padding:.5rem}#review-notes>li{padding:.8rem;border-bottom:1px solid #98a7ab}#review-notes .controls button{width:auto}button{cursor:pointer;padding:.5rem .7rem;border:1px solid #98a7ab;border-radius:5px;background:white;color:inherit}button:hover{background:#e9f2f3}:focus-visible{outline:3px solid #b75200;outline-offset:3px}.layout{display:grid;grid-template-columns:minmax(0,2fr) minmax(260px,1fr);gap:1.5rem}video{display:block;width:100%;max-height:65vh;background:#101a20}.controls{display:flex;flex-wrap:wrap;gap:.6rem;align-items:center;margin:.8rem 0}ol{padding-left:1.5rem}li{margin:.4rem 0}li button{text-align:left;width:100%}.current{background:#d8efec;border-left:4px solid #006957}.words{white-space:pre-wrap}.transcript{max-height:60vh;overflow:auto}.time{font-variant-numeric:tabular-nums;color:#40525a}.muted{color:#45575e}#caption-fallback{white-space:pre-wrap;background:#102026;color:white;padding:1rem}input{max-width:95%;padding:.5rem}footer{overflow-wrap:anywhere}noscript{display:block;border:2px solid #9a6400;padding:1rem}@media(max-width:800px){.layout{display:block}.transcript{max-height:none}}@media print{video,.controls,.search,.skip{display:none}.layout{display:block}.transcript{max-height:none;overflow:visible}button{border:0}.current{background:transparent}}",
  )
  out.write_string(
    "</style></head><body><a class=\"skip\" href=\"#screening\">Skip to screening</a><header><h1>" +
    escape_html(self.title) +
    "</h1><p>" +
    escape_html(source_name) +
    " · " +
    @clock.time(self.duration_ms) +
    "</p><p class=\"muted\">Offline editorial screening. This folder contains an exact media copy and operator-selected sidecars. It records no client acceptance, publication permission or delivery.</p></header><main id=\"screening\"><noscript>JavaScript is off. Play the video with its native controls and read the transcript below. Search, caption overlay and click-to-seek need JavaScript. Caption and chapter sidecars can be downloaded below.</noscript><div class=\"layout\"><section aria-label=\"Video screening\"><video id=\"player\" controls preload=\"metadata\" playsinline src=\"media.mp4\" aria-label=\"Screening video\">Your browser needs a local H.264/AAC video player.</video><p id=\"caption-fallback\" hidden></p><div class=\"controls\"><button type=\"button\" data-nudge-ms=\"-5000\">Back 5 seconds</button><button type=\"button\" data-nudge-ms=\"5000\">Forward 5 seconds</button><label>Speed <select id=\"speed\"><option value=\"0.75\">0.75×</option><option value=\"1\" selected>1×</option><option value=\"1.25\">1.25×</option><option value=\"1.5\">1.5×</option><option value=\"2\">2×</option></select></label><button id=\"captions-toggle\" type=\"button\" aria-pressed=\"true\"" +
    (if self.cues.is_empty() { " hidden" } else { "" }) +
    ">Captions on</button></div><p id=\"playback-status\" role=\"status\">Use Play, or choose a chapter or transcript cue to seek. Seeking never starts playback.</p><div class=\"controls\" role=\"group\" aria-label=\"Repeat a review range\"><button id=\"range-start\" type=\"button\">Mark A here</button><button id=\"range-end\" type=\"button\">Mark B here</button><button id=\"range-repeat\" type=\"button\" aria-pressed=\"false\" disabled>Repeat off</button><button id=\"range-clear\" type=\"button\">Clear range</button></div><p id=\"range-status\" role=\"status\">Mark A then B to repeat a review range.</p><h2>Chapters</h2>",
  )
  if self.chapters.is_empty() {
    out.write_string("<p>No chapter draft supplied.</p>")
  } else {
    out.write_string("<ol>")
    for i, chapter in self.chapters {
      out.write_string(
        "<li><button type=\"button\" data-chapter-index=\"" +
        i.to_string() +
        "\" data-seek-ms=\"" +
        chapter.start_ms.to_string() +
        "\"><span class=\"time\">" +
        @clock.time(chapter.start_ms) +
        "</span> " +
        escape_html(chapter.title) +
        "</button></li>",
      )
    }
    out.write_string("</ol>")
  }
  out.write_string(
    "<section aria-labelledby=\"chapter-author-title\"><h3 id=\"chapter-author-title\">Author chapters while watching</h3><p>Start a new set of chapter markers from playback. Session markers use whole milliseconds; supplied native chapters keep their original clock and are unchanged. Capture, label, preview and apply each marker. Download FFmetadata before closing this page.</p><button id=\"chapter-author-capture\" type=\"button\" disabled>Capture chapter start here</button><div id=\"chapter-author-editor\" hidden><label for=\"chapter-author-label\">Chapter label</label><input id=\"chapter-author-label\" type=\"text\" maxlength=\"200\" disabled><label for=\"chapter-author-start\">Start (ms)</label><input id=\"chapter-author-start\" type=\"text\" inputmode=\"numeric\" maxlength=\"16\" disabled><div class=\"controls\"><button id=\"chapter-author-recapture\" type=\"button\" disabled>Use current position</button><button id=\"chapter-author-preview\" type=\"button\" disabled>Preview marker intervals</button><button id=\"chapter-author-apply\" type=\"button\" disabled>Apply marker</button><button id=\"chapter-author-cancel\" type=\"button\" disabled>Cancel edit</button></div></div><p id=\"chapter-author-preview-status\" role=\"status\" hidden></p><p id=\"chapter-author-status\" role=\"status\"></p><ol id=\"chapter-author-list\"></ol><button id=\"chapter-author-download\" type=\"button\" disabled>Download authored chapters (FFmetadata)</button><p class=\"muted\">The final chapter ends at the screening duration. Leading time before the first marker has no chapter. Downloads contain no native project identity and do not change the video, supplied chapter draft, captions or feedback notebook.</p></section></section><section aria-labelledby=\"transcript-title\"><h2 id=\"transcript-title\">Transcript</h2><div class=\"search\"><label for=\"search\">Find spoken text</label><br><input id=\"search\" type=\"search\" placeholder=\"Search supplied captions\"><p id=\"search-count\" role=\"status\">" +
    self.cues.length().to_string() +
    " of " +
    self.cues.length().to_string() +
    " cues</p></div>",
  )
  if self.cues.is_empty() {
    out.write_string(
      "<p>No caption draft supplied. This screening has no supplied caption overlay or transcript.</p>",
    )
  }
  out.write_string("<ol class=\"transcript\">")
  for i, cue in self.cues {
    out.write_string(
      "<li data-cue-index=\"" +
      i.to_string() +
      "\"><button type=\"button\" data-seek-ms=\"" +
      cue.start_ms.to_string() +
      "\"><span class=\"time\">" +
      @clock.time(cue.start_ms) +
      "–" +
      @clock.time(cue.end_ms) +
      "</span><br><span class=\"words\">" +
      escape_html(cue.text) +
      "</span></button><button type=\"button\" data-caption-edit-index=\"" +
      i.to_string() +
      "\">Edit caption " +
      (i + 1).to_string() +
      "</button></li>",
    )
  }
  out.write_string(
    "<li style=\"list-style:none\"><section aria-labelledby=\"caption-resume-title\"><h3 id=\"caption-resume-title\">Resume saved caption corrections</h3><p>Reopen corrected JSON downloaded from this screening. The recorded media SHA-256, duration and cue count must match. Review wording and timing changes before replacing the applied session draft. Download current corrections first to keep a recovery copy. This does not verify the media file or approve captions.</p><label for=\"caption-resume-file\">Saved corrected-caption JSON (up to 16 MiB)</label><input id=\"caption-resume-file\" type=\"file\" accept=\".json,application/json\"><button id=\"caption-resume-apply\" type=\"button\" disabled>Apply previewed saved captions</button><button id=\"caption-resume-cancel\" type=\"button\">Cancel saved draft preview</button><p id=\"caption-resume-status\" role=\"status\" aria-live=\"polite\">Choose a saved draft to preview. Nothing is uploaded.</p><ol id=\"caption-resume-list\"></ol></section></li>",
  )
  out.write_string(
    "</ol></section></div><section aria-labelledby=\"caption-edit-title\"><h2 id=\"caption-edit-title\">Correct caption wording and timing</h2><p>Edit a supplied cue while screening. Enter whole milliseconds or capture the current playback position. Preview timing corrections, then apply or cancel. Wording-only corrections can be applied directly. Download an ordinary caption draft for the existing caption editor or a WebVTT sidecar. Original files and the supplied context in feedback briefs remain unchanged.</p><p id=\"caption-edit-anchor\" role=\"status\"></p><label for=\"caption-edit-text\">Caption wording</label><br><textarea id=\"caption-edit-text\" rows=\"3\" maxlength=\"2000\" disabled></textarea><div class=\"controls\"><label for=\"caption-edit-start\">Start (ms)</label><input id=\"caption-edit-start\" type=\"text\" inputmode=\"numeric\" maxlength=\"16\" disabled><button id=\"caption-capture-start\" type=\"button\" disabled>Use current position as start</button><label for=\"caption-edit-end\">End (ms)</label><input id=\"caption-edit-end\" type=\"text\" inputmode=\"numeric\" maxlength=\"16\" disabled><button id=\"caption-capture-end\" type=\"button\" disabled>Use current position as end</button></div><div class=\"controls\"><button id=\"caption-preview\" type=\"button\" disabled>Preview correction</button><button id=\"caption-edit-save\" type=\"button\" disabled>Apply correction</button><button id=\"caption-edit-cancel\" type=\"button\" disabled>Cancel edit</button><button id=\"caption-edit-restore\" type=\"button\" disabled>Use supplied wording</button><button id=\"caption-restore-timing\" type=\"button\" disabled>Use supplied timing</button></div><p id=\"caption-preview-status\" role=\"status\" hidden></p><p id=\"caption-edit-status\" role=\"status\"></p><div class=\"controls\"><button id=\"caption-download-json\" type=\"button\" disabled>Download corrected caption draft (JSON)</button><button id=\"caption-download-vtt\" type=\"button\" disabled>Download corrected captions (WebVTT)</button></div><h3>Replace caption wording</h3><p>Case-sensitive literal text, across all captions. Preview before applying; original files remain unchanged.</p><label for=\"caption-replace-find\">Find text</label><input id=\"caption-replace-find\" maxlength=\"2000\"><label for=\"caption-replace-with\">Replace with</label><input id=\"caption-replace-with\" maxlength=\"2000\"><button id=\"caption-replace-preview\" type=\"button\">Preview replacements</button><button id=\"caption-replace-apply\" type=\"button\" disabled>Apply previewed replacements</button><p id=\"caption-replace-status\" role=\"status\"></p><ol id=\"caption-replace-list\"></ol></section><section aria-labelledby=\"review-title\"><h2 id=\"review-title\">Editorial review notes</h2><p>Capture the moment before writing. Notes are local issues, never client acceptance. Download to keep your work before closing this page.</p><div class=\"controls\"><button id=\"review-point\" type=\"button\">Capture current position</button><button id=\"review-range\" type=\"button\">Use marked A–B range</button></div><p id=\"review-anchor\" role=\"status\"></p><label for=\"review-text\">Note text</label><br><textarea id=\"review-text\" rows=\"4\" maxlength=\"2000\"></textarea><div class=\"controls\"><button id=\"review-save\" type=\"button\">Add note</button><button id=\"review-cancel\" type=\"button\">Cancel edit</button></div><label for=\"review-filter\">Show issues </label><select id=\"review-filter\"><option value=\"all\">All</option><option value=\"open\">Open</option><option value=\"resolved\">Resolved</option></select><div class=\"controls\"><label for=\"review-search\">Find note text</label><input id=\"review-search\" type=\"search\" maxlength=\"2000\" placeholder=\"Search saved issues\"><label for=\"review-chapter\">Chapter scope</label><select id=\"review-chapter\"></select><label for=\"review-order\">List order</label><select id=\"review-order\"><option value=\"created\">Notebook order</option><option value=\"timeline\">Timeline order</option></select></div><div class=\"controls\"><button id=\"review-previous\" type=\"button\" disabled>Previous matching issue</button><button id=\"review-next\" type=\"button\" disabled>Next matching issue</button></div><p id=\"review-navigation\" role=\"status\"></p><p id=\"review-status\" role=\"status\"></p><div class=\"controls\"><button id=\"review-undo\" type=\"button\" disabled>Undo notebook change</button><button id=\"review-redo\" type=\"button\" disabled>Redo notebook change</button></div><p id=\"review-history-status\" role=\"status\"></p><ol id=\"review-notes\"></ol><div class=\"controls\"><button id=\"review-download\" type=\"button\">Download notebook</button><label for=\"review-file\">Load notebook JSON (up to 10 files) </label><input id=\"review-file\" type=\"file\" accept=\".json,application/json\" multiple><button id=\"review-apply\" type=\"button\" disabled>Replace current notebook</button><button id=\"review-merge\" type=\"button\" disabled>Merge into current notebook</button><button id=\"review-revision-open\" type=\"button\" disabled>Review selected notebook revisions</button><button id=\"review-discard-import\" type=\"button\" disabled>Cancel loaded notebooks</button></div><section id=\"review-revision-panel\" aria-labelledby=\"review-revision-title\" hidden><h3 id=\"review-revision-title\">Choose notebook revisions</h3><p>Use this only for a deliberately revised copy of your current notebook. Matching local IDs propose a correspondence, not reviewer identity or common history. Compare every current/incoming time, wording and status before selecting a replacement. For unrelated reviewer files, use Merge instead. Download your current notebook first to keep a recovery copy.</p><p id=\"review-revision-status\" role=\"status\"></p><ol id=\"review-revision-list\"></ol><div class=\"controls\"><button id=\"review-revision-apply\" type=\"button\" disabled>Apply selected revisions</button><button id=\"review-revision-cancel\" type=\"button\">Cancel revision review</button></div></section><h3>Readable feedback brief</h3><p>Save a standalone reading and printing copy with timecodes and supplied caption/chapter context. This does not save an editable notebook or send feedback.</p><div class=\"controls\"><label for=\"review-brief-scope\">Feedback brief scope</label><select id=\"review-brief-scope\"><option value=\"matching\" selected>Current triage matches</option><option value=\"all\">All saved notes</option></select><button id=\"review-brief-download\" type=\"button\" disabled>Download feedback brief (HTML)</button></div><p id=\"review-brief-status\" role=\"status\"></p><p id=\"review-import-status\" role=\"status\"></p><details><summary>Inspect selected files and proposed additions</summary><ol id=\"review-merge-preview\"></ol></details></section></main><footer><h2>Local files</h2><p><a href=\"media.mp4\" download>Download video</a> · <a href=\"result.json\">Bundle manifest</a>",
  )
  if !self.cues.is_empty() {
    out.write_string(
      " · <a href=\"captions.vtt\" download>WebVTT captions</a> · <a href=\"captions.json\" download>Editable caption draft</a>",
    )
  }
  if !self.chapters.is_empty() {
    out.write_string(
      " · <a href=\"chapters.vtt\" download>Chapter WebVTT</a> · <a href=\"chapters.json\" download>Editable chapters</a>",
    )
  }
  out.write_string(
    "</p><p>Source SHA-256: <span id=\"screening-source-sha256\">" +
    escape_html(source_sha256) +
    "</span></p><p>Keep the entire folder together. Browser codec support varies; the media and sidecars also work with an appropriate local player. No login or access control is provided by this folder.</p></footer><script type=\"application/json\" id=\"screening-data\">",
  )
  out.write_string(script_data(self))
  out.write_string(
    "</script><script>\n" + player_script() + "\n</script></body></html>\n",
  )
  out.to_string()
}
