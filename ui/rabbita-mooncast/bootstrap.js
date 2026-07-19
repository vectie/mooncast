const browserPath = globalThis.location?.pathname || '/'
const mountPrefix = browserPath === '/apps/mooncast' || browserPath.startsWith('/apps/mooncast/')
  ? '/apps/mooncast'
  : ''
const path = browserPath.slice(mountPrefix.length) || '/'

// Keep these imports literal: Vite must include every compiled MoonBit surface
// in the release instead of leaving a development-only build path in the
// browser. The route still selects and executes exactly one application.
const loadStudio = () => import('./_build/js/release/build/studio/studio.js')
const loadEditor = () => import('./_build/js/release/build/editor/editor.js')
const loadClient = () => import('./_build/js/release/build/client/client.js')

if (path === '/editor' || path.startsWith('/editor/')) {
  void import('./styles/editor.css')
  void loadEditor()
} else if (path === '/client' || path.startsWith('/client/')) {
  void loadClient()
} else {
  void import('./studio/studio.css')
  void loadStudio()
}
