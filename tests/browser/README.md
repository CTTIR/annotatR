# Widget qualification

Run from the repository root. The R fixture uses this checkout via `pkgload`, the
real canvas module and state transitions, two independent Shiny outputs, and a
synthetic SVG image. It does not require an image decoder or private image files.
It requires the package's Shiny test dependencies and `testthat`.

```sh
Rscript tests/browser/widget-app.R
```

In another terminal, run Chromium through Playwright:

```sh
node tests/browser/widget.cjs
```

Set `PLAYWRIGHT_MODULE` to a module path if Playwright is not installed in the
normal Node module search path. Set `CHROMIUM_PATH` to use a particular Chromium
executable. The defaults use `require('playwright')` and Playwright's browser.
`ANNOTATR_BROWSER_PORT` changes the fixture port (default 5818), and
`ANNOTATR_BROWSER_URL` changes the runner URL (default `http://127.0.0.1:5818`).
Set `ANNOTATR_BROWSER_ARTIFACT_DIR` to save a screenshot and JSON evidence.
Stop the R process after qualification.

The runner asserts even-odd hole pixels and clicks, a MultiPolygon edit through
Shiny that preserves IDs, attributes and an anisotropic nonzero stored level,
independent R proxy commands, stale event rejection, actual DOM remount, gesture
cancellation across render identity changes, out-of-order real network image
loads, a pending overlay surviving a same-source render, and clearing a missing source. It waits for output state, message
acknowledgments, image callbacks and pixels; it has no fixed sleeps.

Fast behavioral tests (simulated canvas, not browser qualification):

```sh
node --test tests/audit/widget.test.js tests/audit/keyboard.test.js
Rscript -e 'devtools::test(filter="^widget-events$", reporter="summary", stop_on_failure=TRUE)'
```

The browser protocol is `{entry_id, revision, payload}`. Widget renders and
annotation proxies include `identity`; the app passes the displayed drawing
target as `options.creationTarget = {layer, label}`. Creation payloads include
that gesture-origin `target`. The app rejects missing or invalid targets instead
of assigning a queued drawing to the current selection. Standalone widgets use
their element ID and revision zero when no project identity exists and do not
require a target for drawing/display/proxies. `window.atcanvasIdentity(id)`
returns a copy of a mounted widget's currently rendered entry/revision. Widget
instances expose `dispose()` and also dispose automatically after DOM removal.

## Full app and capability qualification

`app-journey.R` loads the actual product UI/server, creates public synthetic TIFF
inputs (including missing, corrupt and undecodable entries), and substitutes
only canvas image encoding with a synthetic SVG. This isolates native image
encoding from action, geometry, save/resume and queue-recovery qualification.
It uses real TIFF reads and real checkpoints/exports in a temporary directory.

```sh
Rscript tests/browser/app-journey.R
node tests/browser/app-journey.cjs
```

Its default port is 5819. Set the same `ANNOTATR_BROWSER_PORT` / runner
`ANNOTATR_BROWSER_URL` pair when overriding. The runner uses a 1450×980 viewport
and deviceScaleFactor 1.5, then resumes in a 1100×800 viewport. It exercises native
Tab/radio focus, keyboard point/rectangle/polygon geometry, undo/redo, a single
Shift+Enter commit/advance, failed-entry navigation, delayed actual action/form
controls, protected annotations, dirty failed-folder recovery, export download,
and reopening the actual checkpoint in a fresh browser session. A test-only
round-trip input provides rejection barriers; there are no fixed sleeps.

For actual dependency-absence qualification, install the package into an isolated
R library containing its dependencies except `magick`, and set both `R_LIBS_USER`
and `R_LIBS_SITE` to that library. The base R library remains available. Verify
`.libPaths()` and `requireNamespace("magick", quietly=TRUE)` in that process.
Do not remove or alter packages in the user's normal libraries.

```sh
Rscript --vanilla tests/browser/minimal-app.R
node tests/browser/minimal.cjs
```

The minimal fixture defaults to port 5820 and uses the installed package, with
no function mocks: TIFF reads succeed, the PNG example explains its reader
requirement, and the browser shows the missing canvas encoder before editing.
The same Playwright/Chromium/artifact environment overrides apply to every runner.
This configuration is not a claim about every optional-library combination or
all browsers/accessibility criteria. Stop each R fixture process when finished.

Ordinary product actions also use `{entry_id, revision, payload}`. `.at_action()`
buttons capture fields listed in `data-at-fields` at activation. Selection radios
retain native Shiny behavior and send separate `*_intent` inputs with their
original value and layer. `annotatr-state` exposes current failed-entry identity
for navigation, and widget `*_ready` envelopes report decoding readiness.

`node tests/browser/action-origin.cjs` uses the full-app fixture on port 5819 to
withhold actual canvas renders while real Next, Complete, Save and Flag controls
run. It verifies that mutation/selection envelopes retain the displayed entry
and revision; only explicit Next/Previous/Next-pending navigation may use the
current server stamp. It then releases the render and verifies both ordinary
and keyboard Save for retained annotations after the current display fails.
