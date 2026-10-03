"""Generate the independent synthetic analytical reference bundle."""
from collections import Counter
from fractions import Fraction
from pathlib import Path
import hashlib
import json
import sys

import numpy as np


ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent
ROOT.mkdir(parents=True, exist_ok=True)


def write_json(name, value, *, sort_keys=False):
    (ROOT / name).write_text(
        json.dumps(value, indent=2, sort_keys=sort_keys, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def polygon_feature(identifier, label, level, ring, *, image_case):
    return {
        "type": "Feature",
        "id": identifier,
        "geometry": {"type": "Polygon", "coordinates": [ring]},
        "properties": {
            "roi_id": identifier,
            "layer": "analytical",
            "label": label,
            "level": level,
            "source_level": level,
            "coordinate_schema": "annotatR-pixel-level-v1",
            "source": "synthetic-analytical-reference",
            "attributes": {"image_case": image_case},
        },
    }


# Floating analytical cube and membership oracle. The formula and selection
# are independent of annotatR readers, writers, ROI constructors and rasterizers.
cube = np.fromfunction(
    lambda y, x, b: 100 * (b + 1) + 10 * (y + 1) + x + 1,
    (4, 5, 3),
    dtype=float,
)
cube[0, 0, 0] = np.nan
cube[1, 2, 1] = np.inf
cube[2, 3, 2] = -np.inf
cube[3, 4, 2] = np.nan
masks = {"A": np.zeros((4, 5), dtype=bool), "B": np.zeros((4, 5), dtype=bool)}
masks["A"][0:3, 0:3] = True
masks["B"][1:4, 2:5] = True
bitfield = masks["A"].astype("i4") + 2 * masks["B"].astype("i4")


def finite_statistics(mask, *, roi=None):
    rows = []
    for band in range(3):
        selected = cube[:, :, band][mask]
        finite = selected[np.isfinite(selected)]
        row = {
            "band": band + 1,
            "wavelength_nm": [450, 550, 650][band],
            "n_selected": int(selected.size),
            "n_valid": int(finite.size),
            "n_invalid": int(selected.size - finite.size),
            "mean": float(np.mean(finite)),
            "median": float(np.median(finite)),
            "sd": float(np.std(finite, ddof=1)),
            "min": float(np.min(finite)),
            "max": float(np.max(finite)),
            "sum": float(np.sum(finite)),
        }
        if roi is not None:
            row = {"roi": roi, **row}
        rows.append(row)
    return rows


analysis_expected = {
    "shape_yxb": list(cube.shape),
    "invalid_samples_zero_based": [
        [0, 0, 0, "NaN"],
        [1, 2, 1, "+Inf"],
        [2, 3, 2, "-Inf"],
        [3, 4, 2, "NaN"],
    ],
    "roi_cells_zero_based": {"A": "y=0..2,x=0..2", "B": "y=1..3,x=2..4"},
    "bitfield": bitfield.tolist(),
    "n_foreground": int(np.count_nonzero(bitfield)),
    "n_overlap": int(np.count_nonzero(bitfield == 3)),
    "n_background": int(np.count_nonzero(bitfield == 0)),
    "finite_omit_statistics": [
        row for name, mask in masks.items() for row in finite_statistics(mask, roi=name)
    ],
    "union_pixel_statistics": finite_statistics(masks["A"] | masks["B"]),
    "sampling_units": {
        "unique_selected_pixels": 16,
        "selected_roi_memberships": 18,
        "roi_count": 2,
        "image_count": 1,
        "note": "ROI membership totals count the two overlapping cells twice; a unique-pixel image summary does not.",
    },
}
cube.astype("<f4").tofile(ROOT / "cube.dat")
(ROOT / "cube.hdr").write_text(
    "ENVI\n"
    "samples = 5\n"
    "lines = 4\n"
    "bands = 3\n"
    "header offset = 0\n"
    "data type = 4\n"
    "interleave = bip\n"
    "byte order = 0\n"
    "wavelength = {450, 550, 650}\n"
    "wavelength units = nm\n",
    encoding="ascii",
)
np.save(ROOT / "cube.npy", cube, allow_pickle=False)
write_json("analysis-expected.json", analysis_expected)
write_json(
    "analysis-rois.geojson",
    {
        "type": "FeatureCollection",
        "features": [
            polygon_feature(
                "00000000-0000-0000-0000-00000000012a",
                "A",
                0,
                [[0, 0], [3, 0], [3, 3], [0, 3], [0, 0]],
                image_case="analysis-cube",
            ),
            polygon_feature(
                "00000000-0000-0000-0000-00000000012b",
                "B",
                0,
                [[2, 1], [5, 1], [5, 4], [2, 4], [2, 1]],
                image_case="analysis-cube",
            ),
        ],
    },
)


# Agreement oracle. Inputs are literal row-major lists and all ratios use exact
# Fraction arithmetic before a decimal representation is emitted.
def ratio(numerator, denominator):
    if not denominator:
        return None
    exact = Fraction(numerator, denominator)
    return {"fraction": str(exact), "value": numerator / denominator}


def compare(reference, prediction, codes, *, bitfield_case=False):
    left = sum(reference, [])
    right = sum(prediction, [])
    assert len(left) == len(right)
    rows = []
    for value, label in codes:
        truth = [bool(x & value) if bitfield_case else x == value for x in left]
        pred = [bool(x & value) if bitfield_case else x == value for x in right]
        tp = sum(x and y for x, y in zip(truth, pred))
        fp = sum(not x and y for x, y in zip(truth, pred))
        fn = sum(x and not y for x, y in zip(truth, pred))
        rows.append(
            {
                "value": value,
                "label": label,
                "n_true": sum(truth),
                "n_pred": sum(pred),
                "tp": tp,
                "fp": fp,
                "fn": fn,
                "dice": ratio(2 * tp, 2 * tp + fp + fn),
                "iou": ratio(tp, tp + fp + fn),
            }
        )
    result = {
        "reference": reference,
        "prediction": prediction,
        "n_px": len(left),
        "per_class": rows,
    }
    if bitfield_case:
        result["exact_membership_set_agreement"] = ratio(
            sum(x == y for x, y in zip(left, right)), len(left)
        )
        result["categorical_kappa"] = (
            "not defined here: bitfield codes are sets, not mutually exclusive classes"
        )
    else:
        categories = sorted(set(left + right))
        confusion = [
            [sum(x == r and y == c for x, y in zip(left, right)) for c in categories]
            for r in categories
        ]
        n = len(left)
        observed = Fraction(sum(x == y for x, y in zip(left, right)), n)
        count_left, count_right = Counter(left), Counter(right)
        chance = sum(
            (Fraction(count_left[c] * count_right[c], n * n) for c in categories),
            Fraction(0),
        )
        kappa = None if chance == 1 else (observed - chance) / (1 - chance)
        result.update(
            confusion_codes=categories,
            confusion=confusion,
            accuracy=ratio(observed.numerator, observed.denominator),
            chance_agreement=ratio(chance.numerator, chance.denominator),
            kappa=None if kappa is None else ratio(kappa.numerator, kappa.denominator),
        )
    return result


categorical_reference = [[0, 1, 1, 2], [0, 1, 2, 2], [0, 0, 2, 1]]
categorical_prediction = [[0, 1, 2, 2], [0, 1, 2, 0], [1, 0, 2, 1]]
bitfield_reference = [[0, 1, 3, 2], [1, 3, 0, 2], [0, 0, 2, 1]]
bitfield_prediction = [[0, 1, 1, 2], [3, 3, 0, 0], [0, 2, 2, 1]]
remap = {0: 0, 1: 2, 2: 1}
remapped_prediction = [[remap[x] for x in row] for row in categorical_prediction]
agreement_expected = {
    "convention": "Each input is an explicit row-major list. Cells are paired directly; no rasterizer or package reader is used.",
    "absent_class_policy": "A zero union has undefined Dice/IoU represented as null; macro policy must state whether this class is excluded.",
    "categorical": compare(
        categorical_reference,
        categorical_prediction,
        [(1, "A"), (2, "B"), (3, "absent")],
    ),
    "remapped_prediction": {
        "matrix": remapped_prediction,
        "codebook": {"0": "background", "2": "A", "1": "B", "3": "absent"},
        "expected_after_explicit_by_label_alignment": "same as categorical case",
    },
    "bitfield": compare(
        bitfield_reference,
        bitfield_prediction,
        [(1, "A"), (2, "B"), (4, "absent")],
        bitfield_case=True,
    ),
    "background_only": {
        "matrix": [[0, 0], [0, 0]],
        "accuracy": 1,
        "chance_agreement": 1,
        "kappa": None,
        "reason": "Kappa denominator 1-pe is zero; reporting 1 would claim an undefined statistic.",
    },
}
write_json("agreement-expected.json", agreement_expected, sort_keys=True)
for name, values in {
    "categorical-reference.npy": categorical_reference,
    "categorical-prediction.npy": categorical_prediction,
    "categorical-prediction-remapped.npy": remapped_prediction,
    "bitfield-reference.npy": bitfield_reference,
    "bitfield-prediction.npy": bitfield_prediction,
}.items():
    np.save(ROOT / name, np.asarray(values, dtype="<i4"), allow_pickle=False)


# Non-unit physical calibration case. Calibration belongs to level 0; no ROI
# attribute is treated as an implicit or legacy calibration declaration.
physical_expected = {
    "level_dimensions": [[10, 8], [4, 2]],
    "dimension_order": "width,height",
    "level0_pixel_size_um": [0.5, 3],
    "calibration_declared_at_level": 0,
    "stored_roi_level": 1,
    "stored_rectangle_width_height": [2, 1],
    "level1_to_level0_scale_xy": [2.5, 4],
    "geometric_area_level1_px2": 2,
    "geometric_area_level0_px2": 20,
    "physical_area_um2": 30,
    "note": "Geometric area is distinct from raster-selected pixel count. The physical area uses the explicitly level-0 calibration.",
}
write_json("physical-area-expected.json", physical_expected)
write_json(
    "physical-roi-level1.geojson",
    {
        "type": "FeatureCollection",
        "features": [
            polygon_feature(
                "00000000-0000-0000-0000-00000000012c",
                "calibration-case",
                1,
                [[0, 0], [2, 0], [2, 1], [0, 1], [0, 0]],
                image_case="non-unit-anisotropic-grid",
            )
        ],
    },
)


write_json(
    "optional-formats.json",
    {
        "schema_version": 1,
        "repository_license": "MIT + file LICENSE",
        "synthetic_provenance": (
            "All listed repository samples are deterministically generated synthetic data; "
            "none contains acquired, patient, vendor, or third-party image data."
        ),
        "contains_acquired_or_third_party_image_data": False,
        "optional_formats": [
            {
                "format": "OME-TIFF",
                "sample_path": "tests/testthat/fixtures/readers/images/reference.ome.tif",
                "provenance": "synthetic reader-contract sample generated by tests/testthat/fixtures/readers/images/generate.py",
                "license": "MIT + file LICENSE",
                "qualification": "positive optional qualification with RBioFormats 1.12.0 and BioFormats 7.3.0; see T07-report.md",
                "claim_limit": "tiny CYX/pyramid contract only; not broad vendor or whole-slide support",
            },
            {
                "format": "SpecCube",
                "sample_path": "tests/testthat/fixtures/readers/binary/reference_SpecCube.dat",
                "provenance": "synthetic big-endian float32 format-contract sample generated by tests/testthat/fixtures/readers/binary/generate.py",
                "license": "MIT + file LICENSE",
                "qualification": "mandatory synthetic format-contract fixture",
                "claim_limit": "not a proprietary camera output qualification",
            },
            {
                "format": "vendor/acquired whole-slide formats",
                "sample_path": None,
                "provenance": None,
                "license": None,
                "qualification": "unavailable; no support claim",
                "claim_limit": "no vendor, qptiff, acquired, or private sample is bundled",
            },
        ],
    },
)


generated = sorted(
    path
    for path in ROOT.iterdir()
    if path.is_file()
    and path.name not in {"generate.py", "README.md", "MD5SUMS", "SHA256SUMS"}
)
(ROOT / "MD5SUMS").write_text(
    "".join(f"{hashlib.md5(path.read_bytes()).hexdigest()}  {path.name}\n" for path in generated),
    encoding="ascii",
)
(ROOT / "SHA256SUMS").write_text(
    "".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in generated),
    encoding="ascii",
)

assert analysis_expected["n_foreground"] == 16
assert analysis_expected["n_overlap"] == 2
assert analysis_expected["n_background"] == 4
assert analysis_expected["union_pixel_statistics"][0]["sum"] == 1937
assert agreement_expected["categorical"]["accuracy"]["fraction"] == "3/4"
assert agreement_expected["categorical"]["kappa"]["fraction"] == "5/8"
assert agreement_expected["categorical"]["confusion"] == [[3, 1, 0], [0, 3, 1], [1, 0, 3]]
print(
    "Independent analytical reference: 16 unique foreground pixels, "
    "2 overlap cells, exact categorical kappa 5/8, physical area 30 um^2."
)
