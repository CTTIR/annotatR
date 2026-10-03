# Native QuPath 0.7.0 fixture

`native-array.geojson` is the exact native PathIO.exportObjectsAsGeoJSON output
from the independent consumer probe, QuPath 0.7.0 (2026-02-25, commit 04ccfa4).
It contains synthetic geometry only: rectangle bounds [8,6,20,14], area 96,
colour #123456, locked; and a donut of area 84, colour #ABCDEF. The original
IDs are level-roi and donut-roi, mapped through valid native UUIDs and string
metadata. QuPath emitted identical repeated metadata objects; bytes are retained
to exercise the parser's duplicate-key boundary without reserialization.

The portable live qualification is tests/qualification/qupath-roundtrip.R plus
its Groovy consumer. Supply a QuPath executable or a Java command/classpath as
arguments; no installation path is embedded in runtime or qualification code.
