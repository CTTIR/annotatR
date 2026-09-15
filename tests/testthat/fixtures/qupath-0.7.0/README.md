# QuPath 0.7.0 interchange fixtures

Written and read by a real QuPath 0.7.0 installation (headless, system OpenJDK 25.0.4,
`java -Djava.awt.headless=true -cp "<QuPath>/lib/app/*" qupath.QuPath script <file.groovy>`)
on 2026-09-14. The Groovy scripts and full provenance (hashes, exit codes) are in
`data-raw/qupath-fixtures/`.

| File | Produced by | Role in tests |
|---|---|---|
| `qupath_written_objects.geojson` | QuPath `PathIO.exportObjectsAsGeoJSON(..., "FEATURE_COLLECTION")` | independent input for `at_read_qupath()` / `at_import_qupflowr()` |
| `qupath_written_objects_array.geojson` | same objects, exported without options (bare array) | bare-array variant |
| `qupath_written_expected.json` | the write script, from its *input values* (not by re-reading the export) | expected values (types, classes, colours, lock, vertices, planes, measurements) |
| `annotatr_written_qupath.geojson` | annotatR 0.1.0 `at_write_qupath()` (legacy dialect) | input QuPath read |
| `qupath_reads_annotatr.json` | QuPath `PathIO.readObjects()` on the file above | what QuPath understood from annotatR's legacy dialect |
| `annotatr_020_qupath_dialect.geojson` | annotatR 0.2.0 `at_write_qupath()` (default QuPath dialect) | input for QuPath read and re-export |
| `qupath_reads_annotatr020.json` | QuPath read of the 0.2.0 file (ids, classes, planes, metadata) | QuPath keeps the written UUIDs and `annotatr_*` metadata |
| `qupath_roundtrip_annotatr020.geojson` | QuPath `exportObjectsAsGeoJSON(FEATURE_COLLECTION)` of those objects | annotatR restores its ids after a QuPath round trip; QuPath writes `metadata` twice per feature |

No image data, vendor data or patient data are involved; the objects live in a synthetic
200 x 150 px coordinate space.
