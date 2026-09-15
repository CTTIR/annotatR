# Provenance: QuPath 0.7.0 GeoJSON interchange fixtures

Generated 2026-09-14 (local time, UTC+02:00). Everything here was produced by a real QuPath 0.7.0
installation; nothing in the `.json` / `.geojson` outputs was typed by hand.

## Environment

| item | value |
|---|---|
| QuPath | `/opt/QuPath-v0.7.0`, `qupath.lib.common.GeneralTools.getVersion()` = `0.7.0` |
| qupath-core jar sha256 | `31fbcd9e19544bf50a3ca00c8792eb0e94da9b0fb9182bd3c8ec3d77130ded61` (`lib/app/qupath-core-0.7.0.jar`) |
| qupath app jar sha256 | `26f82345ac2404f8bd05113a0cfad48b2c3d82e14c021d0b0ad285d1dce1642e` (`lib/app/qupath-0.7.0.jar`) |
| Java used | system OpenJDK `25.0.4` 2026-07-21 (build 25.0.4+7-1-26.04-Ubuntu), `/usr/lib/jvm/java-25-openjdk-amd64` |
| Bundled runtime | `lib/runtime` reports `JAVA_VERSION="25.0.2"` but contains no `bin/java`, so it was not used |
| OS | Ubuntu 26.04 LTS, Linux 7.0.0-29-generic x86_64 |
| Other libs on the classpath | groovy 5.0.4, gson 2.13.2, jts-core 1.20.0, logback 1.5.23 |

## How QuPath was run

The scripts read and write in the current working directory (`System.getProperty("user.dir")`),
so every command below was run from this directory.

1. `/opt/QuPath-v0.7.0/bin/QuPath script hello.groovy` (2026-09-14T17:01:05+02:00):
   **exit 139** (segfault), stdout and stderr both empty.
2. `JAVA_TOOL_OPTIONS=-Djava.awt.headless=true /opt/QuPath-v0.7.0/bin/QuPath script hello.groovy`:
   **exit 139**, stdout and stderr both empty. There was not even a JVM "Picked up JAVA_TOOL_OPTIONS"
   line, so the native jpackage launcher probably crashes before the JVM starts. Not investigated further.
3. It worked with the system java and QuPath's classpath (2026-09-14T17:01:21+02:00, **exit 0**,
   printed `version=0.7.0`):
   ```
   java -Djava.awt.headless=true -XX:MaxRAMPercentage=50 --enable-native-access=ALL-UNNAMED \
        -cp "/opt/QuPath-v0.7.0/lib/app/*" qupath.QuPath script hello.groovy
   ```
   Attempt (c), running with the sandbox disabled, was not needed.

Fixture runs (same invocation without `-XX:MaxRAMPercentage=50`):

| script | command | start | end | exit |
|---|---|---|---|---|
| `explore_api.groovy`, `explore_api2.groovy` | `java -Djava.awt.headless=true --enable-native-access=ALL-UNNAMED -cp "/opt/QuPath-v0.7.0/lib/app/*" qupath.QuPath script <file>` | ~17:01:40, ~17:02:36 | | not captured for `explore_api.groovy` (the recorded 0 is the exit status of the `grep` it was piped into); 0 for `explore_api2.groovy` |
| `qupath_read_test.groovy` | same | 2026-09-14T17:03:30+02:00 | 17:03:33 | **0** |
| `qupath_write_test.groovy` (final run; an earlier run at 17:05:33 used `new GeometryFactory()` and was overwritten) | same | 2026-09-14T17:06:31+02:00 | 17:06:34 | **0** |
| `probe_precision_roundtrip.groovy` (extra probe, output to stdout only) | same | ~17:07:30 | 2026-09-14T17:07:32+02:00 | **0** |

Stdout/stderr of each run are in `logs/` (`*.out`, `*.err`, `*.run`). The only QuPath log lines
besides startup INFO messages were:
* read test: `WARN q.l.i.QuPathTypeAdapters$PathObjectTypeAdapter - PathObject using 'object_type' property - this should be updated to 'objectType'`
  (logged once, even though all 4 features use `object_type`)
* first write run only: `WARN qupath.lib.roi.GeometryROI - Geometry precision model for ROI Floating does not match default precision model Fixed (Scale=100.0)`.
  The final run uses `GeometryTools.getDefaultFactory()`, which removes this warning.

## Files and sha256

Computed with `sha256sum` after the final runs.

| file | role | sha256 |
|---|---|---|
| `annotatr_written_qupath.geojson` | input (annotatR-written, not produced here) | `51264a043e7512338d5837da83a0c1d9604314033f863b8ad52452a9905af494` |
| `qupath_reads_annotatr.json` | read test output | `3714dc70b04abe4183c49c51bc4a654b74fd6ebf0ebb20f8f103dea58aad14a2` |
| `qupath_written_objects.geojson` | write test, `FEATURE_COLLECTION` | `6f3aa8653b30f9baec7c29a9fc6a5d0ffb25bbf3e3c78d962c16947037155a3d` |
| `qupath_written_objects_array.geojson` | write test, no options (bare JSON array) | `71357fc0b0b90931eff4861078f67aeedd4ac37df6c1aa51ecb1c0c5ed110aa8` |
| `qupath_written_objects_pretty.geojson` | write test, `FEATURE_COLLECTION` + `PRETTY_JSON` | `7fb2f62db5667cf0cc3ce434455271ee12d7b56b456444fa28b2024554dde0a6` |
| `qupath_written_expected.json` | independent description of the created objects | `48ebb32c644dc042b120c254dc9afa14e02b8dccda0aa52750f00e0b3f87bad0` |
| `qupath_read_test.groovy` | script | `09a4ee86fcf179d7805586a8dbf7d935d6d057e89b4fe6439a67b9eea5fa7261` |
| `qupath_write_test.groovy` | script | `e295eac4832f80a7a42692d7238b43e7b11e5471adc65bf04bc992b8e0981372` |
| `probe_precision_roundtrip.groovy` | script (extra probe) | `d39f7a0132062d405fd83622aca4033542e5bc6cb7c5081bd4a969b23b4ce223` |
| `hello.groovy` | launcher smoke test | `aeb90441a311bedd322eb7174f766853a09bb748c82ad8d1d1d13a7f95a57a07` |
| `explore_api.groovy` | API reflection dump | `8cb53511d59a75b4dbe22fc2b7739c6398e330f7a3c0554bf24294b41fc61637` |
| `explore_api2.groovy` | API reflection dump | `9abf04f35e9958b3df3a2045aa914178898b667e2e0c1400aef927fe33ccbf5f` |
| `logs/read_test.out` | stdout | `814f348423d94564e8211b4646984a47b631f09f92a65f0550e6e21f108d40f1` |
| `logs/write_test.out` | stdout | `cb4bde0cf14908507d8aa69e8519a9fb4cfac2516e9551264185836922833b2b` |
| `logs/probe.out` | stdout | `bc790eb84f0626746d93cad3a4d07af3e50e13b6e7b4cf57baed1536383da553` |
| `logs/b1.out` | stdout | `e814b1decd53477b89367e48a043b1fdbba2c61c04d31bb2c55890c4a53641df` |
| `logs/read_test.run` / `write_test.run` / `probe.run` | timestamps + exit codes | `128a56ed…91dc7` / `e4f9825d…cf442` / `7a1b8bb4…b041` |
| `logs/api.txt` / `logs/api2.txt` | reflection output | `1041e000…67bb` / `f54cda2e…33f5` |
| `logs/a1.*`, `a2.*`, `b1.err`, `*.err` | empty | `e3b0c442…b855` (empty file) |

**Determinism:** only object (a) has a fixed UUID. The write script gives every other object a new
random UUID on each run, so re-running changes the ids in all four write outputs. The file sizes stay
the same (3680 / 3640 / 6901 bytes in both write runs). `qupath_written_expected.json` records the
ids of its own run, and they match the exported feature ids in order. The ids in
`qupath_reads_annotatr.json` are also random per run, because QuPath replaced the non-UUID input ids.

## Format facts observed (QuPath 0.7.0)

### Export (`PathIO.exportObjectsAsGeoJSON`)
* Options enum `PathIO.GeoJsonExportOptions` = `PRETTY_JSON, EXCLUDE_MEASUREMENTS, FEATURE_COLLECTION`.
* With `FEATURE_COLLECTION` the output is `{"type":"FeatureCollection","features":[...]}`. With no
  options it is a bare JSON array `[Feature, ...]`; the features themselves are identical.
  `PRETTY_JSON` parses to the same JSON as the compact file (checked with Python `json`). None of the
  three export files ends with a newline.
* Pretty print uses 2-space indentation, but each coordinate pair stays on one line (`[10, 20]`).
  The compact files are one line each. They put a space after the comma only inside numeric arrays
  (coordinate pairs `[10, 20]` and colour `[200, 0, 0]`), with no whitespace anywhere else and none
  between coordinate pairs (`],[`).
* Feature key order: `type`, `id`, `geometry`, [`nucleusGeometry`], `properties`.
* **id:** the UUID is written as the feature-level `"id"` string (e.g. `"11111111-1111-4111-8111-111111111111"`).
  `PathObject.setID(UUID)` works, and re-reading restores the id.
* **Object type:** `properties.objectType` (camelCase), with values `"annotation"`, `"detection"`, `"cell"`.
* **Name:** `properties.name`. It is omitted when null.
* **Classification:** `properties.classification = {"name":"Tumor","color":[200, 0, 0]}`, with colour as an
  `[r,g,b]` int array. There is no `colorRGB` on export. A derived class is written as
  `{"names":["Tumor","Positive"],"color":[200, 50, 50]}` (key `names`, an array, and no `name`).
  Unclassified objects have no `classification` key.
* **Lock:** `properties.isLocked: true` is written only when locked. It is omitted when false.
* **Plane:** stored **inside the geometry object**, `geometry.plane = {"c":-1,"z":2,"t":1}`, and written
  only for a non-default plane. The default plane (c=-1, z=0, t=0) is omitted.
* **Measurements:** `properties.measurements` is a flat object `{"Area px^2":100.0,"Mean":"NaN"}`.
  Values are written as doubles (`100.0`). **NaN is written as the JSON string `"NaN"`.**
  `MeasurementList.put("Mean", NaN)` is accepted. Objects without measurements have no
  `measurements` key.
* **Cell:** the nucleus is the feature-level key `nucleusGeometry` (a sibling of `geometry`, not inside
  `properties`), and `geometry` is the cell boundary.
* **Ellipse:** polygonised to a `Polygon` with 100 vertices plus the closing vertex (101 coordinates),
  with the marker `geometry.isEllipse: true`. QuPath reads it back as an `Ellipse` ROI with the exact
  area 942.4778. The area of the exported polygon itself is 941.94.
* **Line:** `LineString`. **Points:** `MultiPoint`, including for 3 points.
* **Rectangle:** `Polygon`, 5 coordinates.
* **Coordinate precision:** exported coordinates are rounded to 2 decimal places (probe:
  1.23456 → 1.23, 2.98765 → 2.99, 100.005 → 100.01, 0.001 → 0). Whole numbers are written without a
  decimal point (`10`, not `10.0`).
* **Ring orientation / start vertex:**
  * ROIs built with `ROIs.createRectangleROI`, `createPolygonROI` and `createEllipseROI` are exported
    with a negative shoelace sum in raw (x,y). That is clockwise in a y-up frame, and appears
    counter-clockwise on the y-down image.
  * The vertex order is normalised. The rectangle is written (10,20),(10,70),(60,70),(60,20),(10,20).
    The cell polygon passed as (120,100),(140,100),(145,115),(130,130),(115,115) was written reversed
    and starting at the min vertex: (115,115),(130,130),(145,115),(140,100),(120,100),(115,115).
    The nucleus was treated the same way.
  * A `GeometryROI` built with `GeometryTools.geometryToROI` (the polygon with a hole) was exported
    exactly as passed, shell and hole both positive-shoelace. So QuPath does **not** enforce
    RFC 7946 winding.

### Import (`PathIO.readObjects(File)` on the annotatR file)
* All 4 features were read, with no exceptions and one WARN (legacy `object_type`, see above).
* `properties.object_type` is accepted as a legacy key: `"detection"` became a `PathDetectionObject`
  and `"annotation"` became a `PathAnnotationObject`.
* `classification.colorRGB` (packed signed int) is accepted.
* **The class colour is a per-name singleton, and the first colour seen wins.** The detection
  `roi-det-4` has class `Tumor` with `colorRGB` -6710887 = rgb(153,153,153), but QuPath reports
  rgb(200,0,0) (-3670016) from the first `Tumor` feature. No warning is logged.
* **Non-UUID feature ids (`roi-rect-1`, …) are silently discarded.** Each object gets a new random UUID,
  so `id_equals_input` is false for all 4, with no warning. Valid UUID ids are kept (confirmed by
  re-reading QuPath's own export).
* `isLocked:false` became unlocked. The unknown property `layer` is silently ignored: it does not
  appear in the metadata and no warning is logged.
* A polygon that is exactly an axis-aligned rectangle is recognised as `RectangleROI` ("Rectangle"),
  for both annotation and detection.
* The polygon with a hole became `GeometryROI` ("Geometry"), with 1 interior ring, area 5500 and
  length 440 (outer and hole perimeters summed).
* A GeoJSON `Point` became a `PointsROI` ("Points") with area 0, length 0 and bounds w=h=0.
* Every object ended up on the default plane c=-1, z=0, t=0.

### Re-reading QuPath's own export (`probe_precision_roundtrip.groovy`, stdout in `logs/probe.out`)
* Id, name, lock, class (including the derived `Tumor: Positive`), colours, plane z=2/t=1,
  measurements (`Mean` back to NaN), the cell nucleus and the Ellipse ROI type were all restored.

---

## Follow-up (2026-09-15): annotatR QuPath dialect (`annotatr_020_qupath_dialect.geojson`)

Same environment and invocation as above: system OpenJDK 25.0.4, QuPath 0.7.0 classpath, run from
this directory.

### Commands and exit codes

| script | command | start | end | exit |
|---|---|---|---|---|
| `qupath_roundtrip_annotatr020.groovy`, first version | `java -Djava.awt.headless=true --enable-native-access=ALL-UNNAMED -cp "/opt/QuPath-v0.7.0/lib/app/*" qupath.QuPath script qupath_roundtrip_annotatr020.groovy` | 07:52:31 | 07:52:34 | 0. No duplicate-key scan yet; outputs overwritten. |
| same, after adding the duplicate-key scan | same | 07:53:20 | 07:53:23 | 0. The JSON recorded 1 exception from a bug in my own scan code (Groovy `map[name]` with name `properties`), not from QuPath. Outputs deleted. |
| same, fixed (**final**) | same | 2026-09-15T07:53:41+02:00 | 07:53:44 | **0**, 0 exceptions |
| same, re-run to check determinism | same | 2026-09-15T07:53:52+02:00 | 07:53:55 | **0**. Both outputs byte-identical to the final run. |
| `probe_metadata_export.groovy` (extra probe, output to stdout only) | same, with `probe_metadata_export.groovy` | 2026-09-15T07:53:23+02:00 | 07:53:25 | **0** |

### Files and sha256

| file | role | sha256 |
|---|---|---|
| `annotatr_020_qupath_dialect.geojson` | input (annotatR-written, not produced here) | `b3d6bdfb0c7719797d5f4601adc244f53efdf7018db524358d0310f202a1affd` |
| `qupath_reads_annotatr020.json` | read results + re-export comparison | `d6c36d6f5b9674eb589a540010075c1785e26b7ac9f9d0aeded21b8db19e0f10` |
| `qupath_roundtrip_annotatr020.geojson` | QuPath re-export (`FEATURE_COLLECTION`) | `0f1afdff9378c7850665588bb6977c0ee57e6996a6154fceb5274a9e04fa60d5` |
| `qupath_roundtrip_annotatr020.groovy` | script | `b67f26a4b9a6e2bdeb1964da7fe30df1e34d38694f74cf866d07ac4d0654041f` |
| `probe_metadata_export.groovy` | script (extra probe) | `c125acde7895c24b4c4a48822843ce2ee788d1d6fc016de1ddda6527d056a798` |
| `logs/roundtrip020.out` / `.run` | stdout / timestamps (final run) | `007e3ed6b055c09cd891c89fa9dd3a1237683a5bc695890fe50f0c2e3b6e8b06` / `8eb0bb8c40295b856bb48dc4fcc23259bb055c13841f0f591fb1fa729ff5c249` |
| `logs/roundtrip020_rerun.out` / `.run` | stdout / timestamps (determinism run) | `1ff906ef530e7957b5be6cb863c3ce6b0ccbf0adce40628c9de2ede1ec4d3213` / `0d69aba3015068496eb6ec55588414feb61fe5594aa422848bd96901399b0775` |
| `logs/probe_metadata.out` / `.run` | stdout / timestamps | `273750402cad8191bd573b51f9a0ec9ce6c07faf4bbb7a74cf098d4990c83c7a` / `876e0200b1dbbd84cfc8f4c6626fea74f35a2e5f26cab9d93903fd1841b380ab` |
| `logs/roundtrip020*.err`, `logs/probe_metadata.err` | empty | `e3b0c442…b855` |

The outputs are deterministic: all ids come from the input, and both runs produced identical hashes.

### Observed facts
* **Read:** `PathIO.readObjects` read 5 objects in file order, with **0 exceptions and 0 log events**
  (no warnings). The legacy `object_type` warning seen with the earlier file does not appear.
* **Ids:** `getID()` equals the feature `id` for all 5 objects. The version-8-style UUIDs such as
  `c667a1d3-a629-8da6-803e-36fb40a3bd1d` are accepted as they are.
* **Metadata after read:** `getMetadata()` returns exactly the 4 input keys and string values for all
  5 objects, detection `roi-det-4` included. `hasMetadata()` is true for all 5.
* **Types, classes, ROIs, planes:**
  * Object types: 4 annotations and 1 `PathDetectionObject`.
  * `roi-rect-1` is locked (true); the others are unlocked.
  * `classification.names` `["Tumor","Positive"]` becomes the derived class `Tumor: Positive`
    (`getName()` = `Positive`, parent/base `Tumor`, colour rgb(200,50,50)), on plane c=-1, z=2, t=1.
  * ROIs: Rectangle (2500), Geometry (area 5500, 1 interior ring), Points (area 0), Rectangle (600),
    Rectangle (100).
* **Class colour, first one wins (again):** the detection's `Tumor` colour `[153,153,153]` is ignored.
  The object reports rgb(200,0,0), and the re-export writes `"color":[200, 0, 0]`.
* **Re-export:**
  * All 5 ids are kept. The metadata values are kept, **but QuPath 0.7.0 writes the `metadata` member
    twice in every feature's `properties`** (`..."metadata":{...},"metadata":{...}`), with identical
    content. This was detected with a streaming JSON scan in the script, and independently with Python
    `json` using `object_pairs_hook`. The input file has no duplicate members.
  * `probe_metadata_export.groovy` shows the same duplication for objects created directly in QuPath
    with `getMetadata().put("k1","v1")`, on an annotation and on a detection. An object without
    metadata gets no `metadata` key. So the duplication comes from QuPath's writer and has nothing to
    do with annotatR's input.
  * Tree parsers that keep one value per name (Gson, Python `json`) see the metadata correctly. Any
    reader that errors on, or accumulates, duplicate names will be affected.
* **Geometry in the re-export:**
  * The polygon with a hole is written with both rings reversed relative to the input: shell
    `(100,90),(180,90),(180,10),(100,10),(100,90)`, hole `(150,30),(150,60),(120,60),(120,30),(150,30)`.
  * The rectangles are written starting at the min vertex, going (x,y)→(x,y+h)→(x+w,y+h)→(x+w,y).
  * The single point is written as GeoJSON `Point`, not `MultiPoint`.
  * The plane is written as `geometry.plane`.
  * `isLocked:true` is kept. The derived class is written as `names`.
