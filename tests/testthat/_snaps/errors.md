# ROI constructor errors are informative

    Code
      at_roi_rect(4, 0, 0, 4, label = "a")
    Condition
      Error:
      ! Rectangle bounds must satisfy `xmax` > `xmin` and `ymax` > `ymin`.
      x Got x [4, 0], y [0, 4].

---

    Code
      at_roi_point("x", 1, label = "a")
    Condition
      Error:
      ! `x` must be a single finite number.
      x You supplied <character> of length 1.

---

    Code
      at_roi_polygon("nope", label = "a")
    Condition
      Error:
      ! `coords` must be a numeric matrix or a list of numeric matrices.
      x You supplied <character>.

# image and tile errors are informative

    Code
      at_read_image("/no/such/file.png")
    Condition
      Error:
      ! `path` must be an existing file.
      x '/no/such/file.png' does not exist.
      i Use `at_example_path()` to locate the bundled sample data.

---

    Code
      at_tile(small_image(), level = 9)
    Condition
      Error:
      ! `level` exceeds the available pyramid levels.
      x Level 9 requested; levels 0, 1, and 2 exist.

---

    Code
      at_dims(small_image(), level = 9)
    Condition
      Error:
      ! `level` exceeds the available pyramid levels.
      x Level 9 was requested but only levels 0, 1, and 2 exist.

# project and mask errors are informative

    Code
      at_project(small_image(), layers = 42)
    Condition
      Error:
      ! `layers` must be an <annot_layer> or a list of them.
      x You supplied <numeric>.

---

    Code
      at_rois(demo_project(), layer = "nope")
    Condition
      Error:
      ! No layer named "nope".
      i Available layers: "tissue" and "tumour".

---

    Code
      at_mask(42)
    Condition
      Error:
      ! `x` must be an <annot_roi>, <annot_layer>, or <annot_project>.

