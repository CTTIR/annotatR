# Independent reference vectors for annotatR's canonical JSON + SHA-256 digest.
# Canonical form: json.dumps(sort_keys=True, separators=(",", ":"), ensure_ascii=False),
# UTF-8 bytes, no trailing newline (the qupflowR bundle_digest rule).
import hashlib, json, sys
cases = {
  "integrity_two_files": {"format_version": "1.0", "files": [
      {"path": "annotations_qupath.geojson", "size_bytes": 1234, "sha256": "a" * 64},
      {"path": "manifest.json", "size_bytes": 56, "sha256": "0123456789abcdef" * 4}]},
  "nested_unicode": {"z": [1, 2, {"b": None, "a": True}], "a": "Gewäbe \"x\"\n", "m": {}, "e": []},
  "empty_object": {},
  "control_payload": {"image_id": "sha256:0011223344556677", "queue_index": 3, "roi_ids": ["roi_000000001", "roi_000000002"]},
}
out = {}
for name, obj in cases.items():
    s = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    out[name] = {"value": obj, "canonical": s, "sha256": hashlib.sha256(s.encode("utf-8")).hexdigest()}
out["_generator"] = {"python": sys.version.split()[0], "rule": "json.dumps(sort_keys=True, separators=(',', ':'), ensure_ascii=False); sha256(utf-8)"}
json.dump(out, open("canonical-json-vectors.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)
print(json.dumps(out, ensure_ascii=False, indent=1))
