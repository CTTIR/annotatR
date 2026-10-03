# Audit evidence: 2026-09-10

Audited revision: `f69bf201f651c845ab496f76e25638bc919d4b13`, annotatR 0.1.0.

This archive preserves the earlier audit so planning does not depend on temporary files. [Current analysis](../../ANALYSIS.md) qualifies the evidence; [the roadmap](../../ROADMAP.md) defines implementation work. Source links and recorded line numbers in [audit.md](audit.md) describe the historical revision.

| Script | Historical output | Purpose |
|---|---|---|
| [reproduce.R](reproduce.R) | [reproduce.log](reproduce.log) | Core mask, coordinate, reader, identity, cache, and export diagnostics |
| [reproduce-app.R](reproduce-app.R) | [reproduce-app.log](reproduce-app.log) | Full Shiny server transitions using temporary example sessions |
| [reproduce-extra.R](reproduce-extra.R) | [reproduce-extra.log](reproduce-extra.log) | Plot, metadata, bitfield, transform, path, and overwrite diagnostics |
| [reproduce-widget.js](reproduce-widget.js) | [reproduce-widget.log](reproduce-widget.log) | Simulated-DOM hole hit-testing and multiwidget routing |

[tests.log](tests.log) is the original existing-suite run. [package-check.log](package-check.log) is the available-dependency check with temporary workspace paths replaced by `<audit-workdir>`. The check excluded manual, test, and vignette execution; tests ran separately. RBioFormats was unavailable. Recorded results are historical, not a claim about later revisions.

Run diagnostic scripts **from the repository root**, each in its own process:

```sh
Rscript planning/evidence/2026-09-10/reproduce.R
Rscript planning/evidence/2026-09-10/reproduce-app.R
Rscript planning/evidence/2026-09-10/reproduce-extra.R
node planning/evidence/2026-09-10/reproduce-widget.js
```

The R scripts require the package's installed development/test dependencies, including pkgload and the image/Shiny dependencies used by their fixtures. They use synthetic/local bundled images, source the existing test helper, and write only temporary diagnostic files. Source paths were changed from the original machine's absolute path to paths relative to the repository root. Diagnostic logic is otherwise retained. The Node harness uses core Node modules and a simulated canvas/message environment.

These scripts print observations; **a zero exit status does not mean correctness**. Some expected diagnostic errors are caught and printed. Convert cases to explicit regressions as T00 proceeds. Do not turn known-bad outputs into passing test expectations. Keep this historical evidence unchanged and save new runs separately.

The audit did not verify real-browser behavior, all optional formats, remote CI, complete dependency/security history, or real large-slide memory behavior. See [VALIDATION.md](../../VALIDATION.md) for the checks needed to close those gaps.
