// atcanvas: a self-contained HTML5 canvas widget for ROI annotation.
//
// No external libraries: this works fully offline. The R interface matches what
// an OpenSeadragon + Annotorious implementation would need, so that engine can
// be dropped in later without changing the R side.
//
// COORDINATE DISCIPLINE: the drawing space is the level-0 image pixel space
// (tileSource.width x tileSource.height). All coordinates emitted to R are
// level-0 image pixels; toImageCoords() is the single conversion point.

HTMLWidgets.widget({
  name: "atcanvas",
  type: "output",

  factory: function (el, width, height) {
    var canvas = document.createElement("canvas");
    canvas.className = "atcanvas-canvas";
    canvas.style.width = "100%";
    canvas.style.height = "100%";
    canvas.style.cursor = "grab";
    el.appendChild(canvas);
    var ctx = canvas.getContext("2d");

    var state = {
      imgW: 1, imgH: 1, baseImg: null, overlayImg: null, overlayAlpha: 0.5,
      zoom: 1, panX: 0, panY: 0, tool: "pan",
      features: [], drawing: null, selected: null
    };

    function resize() {
      var r = el.getBoundingClientRect();
      canvas.width = r.width; canvas.height = r.height;
      render();
    }

    // Screen (canvas) pixel -> level-0 image pixel.
    function toImageCoords(sx, sy) {
      return [(sx - state.panX) / state.zoom, (sy - state.panY) / state.zoom];
    }
    // Level-0 image pixel -> screen pixel.
    function toScreen(ix, iy) {
      return [ix * state.zoom + state.panX, iy * state.zoom + state.panY];
    }

    function fitBounds(bbox) {
      var x0, y0, x1, y1;
      if (bbox) { x0 = bbox[0]; y0 = bbox[1]; x1 = bbox[2]; y1 = bbox[3]; }
      else { x0 = 0; y0 = 0; x1 = state.imgW; y1 = state.imgH; }
      var bw = Math.max(1, x1 - x0), bh = Math.max(1, y1 - y0);
      state.zoom = Math.min(canvas.width / bw, canvas.height / bh);
      state.panX = -x0 * state.zoom + (canvas.width - bw * state.zoom) / 2;
      state.panY = -y0 * state.zoom + (canvas.height - bh * state.zoom) / 2;
      render();
    }

    function drawFeature(f, isDraw) {
      var g = f.geometry;
      ctx.beginPath();
      if (g.type === "Point") {
        var p = toScreen(g.coordinates[0], g.coordinates[1]);
        ctx.arc(p[0], p[1], 4, 0, 2 * Math.PI);
      } else if (g.type === "Polygon" || g.type === "LineString") {
        var ring = g.type === "Polygon" ? g.coordinates[0] : g.coordinates;
        ring.forEach(function (c, i) {
          var p = toScreen(c[0], c[1]);
          if (i === 0) ctx.moveTo(p[0], p[1]); else ctx.lineTo(p[0], p[1]);
        });
        if (g.type === "Polygon") ctx.closePath();
      }
      ctx.lineWidth = 2;
      ctx.strokeStyle = isDraw ? "#5E2C8E" : (f.properties && f.properties.colour) || "#E69F00";
      ctx.fillStyle = "rgba(94,44,142,0.15)";
      ctx.fill();
      ctx.stroke();
    }

    function render() {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      if (state.baseImg) {
        var tl = toScreen(0, 0);
        ctx.drawImage(state.baseImg, tl[0], tl[1],
          state.imgW * state.zoom, state.imgH * state.zoom);
      }
      if (state.overlayImg) {
        var otl = toScreen(0, 0);
        ctx.globalAlpha = state.overlayAlpha;
        ctx.drawImage(state.overlayImg, otl[0], otl[1],
          state.imgW * state.zoom, state.imgH * state.zoom);
        ctx.globalAlpha = 1;
      }
      state.features.forEach(function (f) { drawFeature(f, false); });
      if (state.drawing) drawFeature(state.drawing, true);
    }

    function shinyInput(suffix, value) {
      if (window.Shiny && el.id) {
        Shiny.setInputValue(el.id + "_" + suffix, value, { priority: "event" });
      }
    }

    function loadImage(uri, cb) {
      if (!uri) { cb(null); return; }
      var im = new Image();
      im.onload = function () { cb(im); };
      im.src = uri;
    }

    // ---- Hit-testing and geometry helpers (for erase / edit) ----
    function pointInRing(pt, ring) {
      var x = pt[0], y = pt[1], inside = false;
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        var xi = ring[i][0], yi = ring[i][1], xj = ring[j][0], yj = ring[j][1];
        if (((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) {
          inside = !inside;
        }
      }
      return inside;
    }
    // Topmost (last-drawn) feature containing the image-space point, or null.
    function featureAt(ic) {
      for (var k = state.features.length - 1; k >= 0; k--) {
        var g = state.features[k].geometry;
        if (g.type === "Polygon" && pointInRing(ic, g.coordinates[0])) return state.features[k];
        if (g.type === "Point") {
          var d = Math.hypot(ic[0] - g.coordinates[0], ic[1] - g.coordinates[1]);
          if (d < 6 / state.zoom) return state.features[k];
        }
      }
      return null;
    }
    function circlePoly(c, r) {
      var pts = [];
      for (var a = 0; a < 40; a++) { var t = a / 40 * 2 * Math.PI; pts.push([c[0] + r * Math.cos(t), c[1] + r * Math.sin(t)]); }
      pts.push(pts[0].slice()); // close the ring EXACTLY: sf/GeoJSON require last coord identical to first
      return pts;
    }
    function translateFeature(f, dx, dy) {
      var g = f.geometry;
      var shift = function (ring) { return ring.map(function (p) { return [p[0] + dx, p[1] + dy]; }); };
      if (g.type === "Polygon") g.coordinates = g.coordinates.map(shift);
      else if (g.type === "LineString") g.coordinates = shift(g.coordinates);
      else if (g.type === "Point") g.coordinates = [g.coordinates[0] + dx, g.coordinates[1] + dy];
    }

    // ---- Pointer interaction ----
    var dragging = false, last = null, polyPts = null;

    canvas.addEventListener("mousedown", function (e) {
      var rect = canvas.getBoundingClientRect();
      var sx = e.clientX - rect.left, sy = e.clientY - rect.top;
      var ic = toImageCoords(sx, sy);
      if (state.tool === "pan") {
        dragging = true; last = [sx, sy]; canvas.style.cursor = "grabbing";
      } else if (state.tool === "rect") {
        state.drawing = { type: "Feature", geometry: { type: "Polygon", coordinates: [[[ic[0], ic[1]]]] }, _start: ic };
      } else if (state.tool === "point") {
        emitCreated({ type: "Point", coordinates: [ic[0], ic[1]] });
      } else if (state.tool === "polygon" || state.tool === "freehand") {
        if (!polyPts) polyPts = [];
        polyPts.push([ic[0], ic[1]]);
        state.drawing = { type: "Feature", geometry: { type: "Polygon", coordinates: [polyPts.concat([polyPts[0]])] } };
        render();
      } else if (state.tool === "circle") {
        state.drawing = { type: "Feature", geometry: { type: "Polygon", coordinates: [[[ic[0], ic[1]]]] }, _center: ic };
      } else if (state.tool === "erase") {
        var eh = featureAt(ic);
        if (eh && eh.properties && eh.properties.roi_id) shinyInput("erased", eh.properties.roi_id);
      } else if (state.tool === "edit") {
        var mh = featureAt(ic);
        if (mh) state.editing = { feature: mh, start: ic,
          id: mh.properties && mh.properties.roi_id,
          layer: mh.properties && mh.properties.layer,
          label: mh.properties && mh.properties.label };
      }
    });

    canvas.addEventListener("mousemove", function (e) {
      var rect = canvas.getBoundingClientRect();
      var sx = e.clientX - rect.left, sy = e.clientY - rect.top;
      if (dragging && last) {
        state.panX += sx - last[0]; state.panY += sy - last[1];
        last = [sx, sy]; render();
      } else if (state.drawing && state.tool === "rect") {
        var ic = toImageCoords(sx, sy), s = state.drawing._start;
        state.drawing.geometry.coordinates = [[[s[0], s[1]], [ic[0], s[1]], [ic[0], ic[1]], [s[0], ic[1]], [s[0], s[1]]]];
        render();
      } else if (state.drawing && state.tool === "freehand") {
        var ic2 = toImageCoords(sx, sy);
        polyPts.push([ic2[0], ic2[1]]);
        state.drawing.geometry.coordinates = [polyPts.concat([polyPts[0]])];
        render();
      } else if (state.drawing && state.tool === "circle") {
        var icc = toImageCoords(sx, sy), cc = state.drawing._center;
        state.drawing.geometry.coordinates = [circlePoly(cc, Math.hypot(icc[0] - cc[0], icc[1] - cc[1]))];
        render();
      } else if (state.editing && state.tool === "edit") {
        var ice = toImageCoords(sx, sy);
        translateFeature(state.editing.feature, ice[0] - state.editing.start[0], ice[1] - state.editing.start[1]);
        state.editing.start = ice;
        render();
      }
    });

    canvas.addEventListener("mouseup", function (e) {
      if (dragging) { dragging = false; canvas.style.cursor = "grab"; emitViewport(); return; }
      if (state.drawing && state.tool === "rect") {
        emitCreated(state.drawing.geometry); state.drawing = null;
      } else if (state.drawing && state.tool === "freehand") {
        emitCreated(state.drawing.geometry); state.drawing = null; polyPts = null;
      } else if (state.drawing && state.tool === "circle") {
        emitCreated(state.drawing.geometry); state.drawing = null;
      } else if (state.editing && state.tool === "edit") {
        var ed = state.editing; state.editing = null;
        if (ed.id) shinyInput("edited", { roi_id: ed.id, layer: ed.layer, label: ed.label, geometry: ed.feature.geometry });
      }
    });

    canvas.addEventListener("dblclick", function () {
      if ((state.tool === "polygon") && state.drawing) {
        emitCreated(state.drawing.geometry); state.drawing = null; polyPts = null;
      }
    });

    canvas.addEventListener("wheel", function (e) {
      e.preventDefault();
      var rect = canvas.getBoundingClientRect();
      var sx = e.clientX - rect.left, sy = e.clientY - rect.top;
      var before = toImageCoords(sx, sy);
      var factor = e.deltaY < 0 ? 1.2 : 1 / 1.2;
      state.zoom *= factor;
      var after = toImageCoords(sx, sy);
      state.panX += (after[0] - before[0]) * state.zoom;
      state.panY += (after[1] - before[1]) * state.zoom;
      render(); emitViewport();
    }, { passive: false });

    function emitCreated(geometry) {
      var f = { type: "Feature", geometry: geometry, properties: {} };
      state.features.push(f); render();
      shinyInput("created", f);
    }
    function emitViewport() {
      shinyInput("viewport", { zoom: state.zoom, center_x: (canvas.width / 2 - state.panX) / state.zoom,
        center_y: (canvas.height / 2 - state.panY) / state.zoom });
    }

    // ---- R -> JS message handlers ----
    if (window.Shiny) {
      var on = function (name, fn) { Shiny.addCustomMessageHandler("atcanvas-" + name, function (m) { if (m.id === el.id) fn(m); }); };
      on("set_annotations", function (m) { state.features = (m.annotations && m.annotations.features) || []; render(); });
      on("set_tool", function (m) { state.tool = m.tool; });
      on("set_band", function (m) { /* band switching requires the tile server; no-op for the embedded base image */ });
      on("set_overlay", function (m) { state.overlayAlpha = m.alpha; loadImage(m.overlay, function (im) { state.overlayImg = im; render(); }); });
      on("fit_bounds", function (m) { fitBounds(m.bbox); });
    }

    window.addEventListener("resize", resize);

    return {
      renderValue: function (x) {
        state.tool = x.tool || "pan";
        state.imgW = x.tileSource.width;
        state.imgH = x.tileSource.height;
        state.features = (x.annotations && x.annotations.features) || [];
        var uri = x.tileSource.dataUri;
        if (uri && uri !== state._lastUri) {
          // New image: load it once and fit the view.
          state._lastUri = uri;
          loadImage(uri, function (im) { state.baseImg = im; resize(); fitBounds(null); });
        } else {
          // Same image (e.g. an ROI was just added): keep the current zoom/pan,
          // do not reload the base image — only redraw the overlay.
          resize();
        }
      },
      resize: function (w, h) { resize(); }
    };
  }
});
