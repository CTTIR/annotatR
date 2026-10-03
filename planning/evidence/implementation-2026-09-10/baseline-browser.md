# Browser baseline

2026-09-10, tracked revision f69bf20, Chromium build 1234 / Playwright local runner.

The actual Shiny annotation app loaded and showed its example image, queue, tools and labels. No page JavaScript errors were observed. This smoke check does not establish correctness of editing, saving or export.

Two real HTML widgets were mounted simultaneously in a Shiny fixture, each showing a donut polygon. Clicking the hole of widget A emitted an `a_erased` event for the surrounding polygon (A24). Separate R proxy buttons sent point-tool commands to A and B; only A emitted a subsequent point event (A25). Widget initialization order meant A held the surviving global handler in this run; the affected widget is not reliably the second widget in UI order.

The fixture and runner currently live at `/tmp/annotatr-roadmap-two-widget.R` and `/tmp/annotatr-roadmap-two-widget.cjs`; T10 will preserve a portable asserting runner and expand it to MultiPolygon, lifecycle, and editing checks. A timed wait was used only in this diagnostic, so it is not a regression test.
