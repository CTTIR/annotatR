# Independent QuPath consumer probe

The pre-T06 snapshot (including reviewed T05 coordinate fixes) exported two synthetic ROIs: level1 rectangle transformed with actual anisotropic image dimensions to bounds `[8,6,20,14]` and area96, and a level0 polygon with one hole and area84. QuPath v0.7.0, build2026-02-25, commit04ccfa4, imported them through its actual PathIO reader and retained geometry, class names, colour values and lock state. Literal geometry/label/lock assertions passed (command exit0).

QuPath's independent `PathIO.exportObjectsAsGeoJSON` then produced a top-level feature array using current `objectType` and classification `color` RGB arrays. annotatR's reader returned zero ROIs without an error for that real native output. Wrapping exactly those features in a FeatureCollection recovers two ROIs, but both colours become palette defaults instead of `#123456` and `#ABCDEF`. This is A31. QuPath also warns about the legacy `object_type` property; current writers should emit `objectType` while readers retain legacy support.

QuPath replaces annotatR's non-UUID feature IDs with generated UUIDs. The current export makes no reversible original-ID mapping available in QuPath's returned data. Preserve original identifiers through explicit supported metadata if claiming a full consumer round trip; otherwise document the native-ID boundary accurately. This observation does not require changing existing internal ROI IDs.

Reproduction scripts, exported input, actual QuPath output and observed data accompany this record. The first attempt to format diagnostics used unavailable `groovy.json.JsonOutput` and failed before import; the corrected script uses QuPath's GsonTools and passes its outbound consumer assertions. The local launcher emits five JVM unknown-JavaFX-module warnings; no global application settings or source files were edited. This is headless consumer API evidence, not GUI interaction or complete format qualification.

Primary references: [QuPath command line](https://qupath.readthedocs.io/en/latest/docs/advanced/command_line.html), [PathIO API](https://qupath.github.io/javadoc/stable/qupath/lib/io/PathIO.html). Local runtime version and literal object data are the evidence for this run.

## Identifier metadata follow-up

A second controlled fixture supplies fixed valid feature UUIDs and `properties.metadata` string entries `annotatR_roi_id` and `annotatR_coordinate_schema`. QuPath preserves both UUIDs and those metadata fields in its native export. Two independent executions produced byte-identical output SHA256 `4f3eae21ad93cdc0de45d457279fa6a749cdb464fe9340e58b266b60c9347cf3`. This confirms a possible original-ID mapping; T09 still must implement and test the package boundary. QuPath0.7.0 emitted identical duplicate `metadata` object keys; that native serialization quirk is recorded, not manufactured by this probe.

The native launcher later exited139 twice before emitting any output (including a version-only invocation). A bounded direct JVM invocation of the same installed QuPath classes succeeds, without changing installation/configuration:

```sh
java -Xmx512m -XX:ActiveProcessorCount=2 --enable-native-access=ALL-UNNAMED -cp '/opt/QuPath-v0.7.0/lib/app/*' qupath.QuPath script /tmp/annotatr-roadmap-qupath-probe/inspect.groovy --args /tmp/annotatr-roadmap-qupath-probe/uuid-input.geojson --args /tmp/annotatr-roadmap-qupath-probe/uuid-observed2.json --args /tmp/annotatr-roadmap-qupath-probe/uuid-roundtrip2.geojson
```

This command exits0 and repeats the literal geometry/label/lock assertions and stable native output. The launcher failure remains separate from package correctness; future qualification can use an explicit command/classpath with the runtime recorded.
