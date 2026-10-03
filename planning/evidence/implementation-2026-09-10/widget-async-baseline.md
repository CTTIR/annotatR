# Widget asynchronous image-load baseline

Observed during roadmap execution, before T10/T11 changed `inst/htmlwidgets/atcanvas.js`. This is a controlled JavaScript callback probe with a simulated canvas, not a real-browser qualification.

Run from the package source directory:

```sh
node planning/evidence/implementation-2026-09-10/widget-async-probe.cjs
```

The probe renders an old entry, then a new entry. It delivers the new image's `onload` first and the delayed old image's callback second. It then renders an input with a missing current image URI. The baseline paints `new-entry`, then incorrectly paints `old-entry`, then retains `old-entry` for the missing URI. The archived JSON contains those observations. Exit zero confirms reproduction of the bad baseline, not correct behavior; T10/T11 regression tests must assert the corrected behavior instead.

T10 addresses callback generations/disposal and gesture provenance. T11 addresses readiness, decode failure, stale-image clearing and editing availability.
