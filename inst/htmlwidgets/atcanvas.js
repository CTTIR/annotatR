// atcanvas: a self-contained HTML5 canvas widget for ROI annotation.
//
// No external libraries: this works fully offline. The R interface matches what
// an OpenSeadragon + Annotorious implementation would need, so that engine can
// be dropped in later without changing the R side.
//
// COORDINATE DISCIPLINE: the drawing space is the level-0 image pixel space
// (tileSource.width x tileSource.height). All coordinates emitted to R are
// level-0 image pixels; toImageCoords() is the single conversion point.

(function () {
  // Shiny stores one handler per message name, so route through live instances.
  var instances = Object.create(null), dispatcherShiny = null, observer = null;
  var methods = ["set_annotations", "set_tool", "set_band", "set_overlay", "fit_bounds"];
  function registerDispatcher() {
    if (window.Shiny && dispatcherShiny !== window.Shiny) {
      dispatcherShiny = window.Shiny;
      methods.forEach(function (name) {
        Shiny.addCustomMessageHandler("atcanvas-" + name, function (m) {
          var instance = instances[m.id];
          if (instance) instance.message(name, m);
        });
      });
    }
    if (!observer && typeof MutationObserver !== "undefined") {
      observer = new MutationObserver(function () {
        Object.keys(instances).forEach(function (id) {
          if (!instances[id].el.isConnected) instances[id].dispose();
        });
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });
    }
  }
  // Keyboard shortcuts read the identity of the app canvas actually rendered.
  window.atcanvasIdentity = function (id) {
    return instances[id] ? instances[id].identity() : null;
  };

HTMLWidgets.widget({
  name: "atcanvas",
  type: "output",

  factory: function (el, width, height) {
    if (instances[el.id]) instances[el.id].dispose();
    var disposed = false, baseGeneration = 0, overlayGeneration = 0, listeners = [];
    var canvas = document.createElement("canvas");
    canvas.tabIndex = 0;
    canvas.setAttribute("aria-label", "Annotation canvas. Arrows move; Enter or Space draws; Escape cancels.");
    var status = document.createElement("div");
    status.setAttribute("role", "status"); status.setAttribute("aria-live", "polite");
    status.className = "atcanvas-status";
    el.appendChild(status);
    canvas.className = "atcanvas-canvas";
    canvas.style.width = "100%";
    canvas.style.height = "calc(100% - 1.5rem)";
    status.style.height = "1.5rem"; status.style.lineHeight = "1.5rem";
    status.style.overflow = "hidden"; status.style.whiteSpace = "nowrap";
    canvas.style.cursor = "grab";
    el.appendChild(canvas);
    var ctx = canvas.getContext("2d");

    var state = {
      imgW: 1, imgH: 1, baseImg: null, overlayImg: null, overlayAlpha: 0.5,
      zoom: 1, panX: 0, panY: 0, tool: "pan", viewW: 1, viewH: 1,
      features: [], drawing: null, selected: null, ready: false, cursor: [0,0]
    };

    function resize() {
      var r = canvas.getBoundingClientRect();
      if (!r.width || !r.height) { state.needsFit = true; return; }
      state.viewW = r.width; state.viewH = r.height;
      var density = window.devicePixelRatio || 1;
      canvas.width = Math.round(r.width * density); canvas.height = Math.round(r.height * density);
      ctx.setTransform(canvas.width / r.width, 0, 0, canvas.height / r.height, 0, 0);
      if (state.needsFit) { state.needsFit = false; fitBounds(null); }
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
      state.zoom = Math.min(state.viewW / bw, state.viewH / bh);
      state.panX = -x0 * state.zoom + (state.viewW - bw * state.zoom) / 2;
      state.panY = -y0 * state.zoom + (state.viewH - bh * state.zoom) / 2;
      render();
    }

    function drawFeature(f, isDraw) {
      if (f.properties && f.properties.visible === false) return;
      var g = f.geometry;
      ctx.beginPath();
      function point(c) {
        var p = toScreen(c[0], c[1]);
        ctx.moveTo(p[0] + 4, p[1]); ctx.arc(p[0], p[1], 4, 0, 2 * Math.PI);
      }
      function line(ring, close) {
        ring.forEach(function (c, i) {
          var p = toScreen(c[0], c[1]);
          if (i === 0) ctx.moveTo(p[0], p[1]); else ctx.lineTo(p[0], p[1]);
        });
        if (close) ctx.closePath();
      }
      function polygon(rings) { rings.forEach(function (ring) { line(ring, true); }); }
      if (g.type === "Point") point(g.coordinates);
      else if (g.type === "MultiPoint") g.coordinates.forEach(point);
      else if (g.type === "LineString") line(g.coordinates, false);
      else if (g.type === "Polygon") polygon(g.coordinates);
      else if (g.type === "MultiPolygon") g.coordinates.forEach(polygon);
      ctx.lineWidth = (f.properties && f.properties.stroke_width) || 2;
      ctx.strokeStyle = isDraw ? "#5E2C8E" : (f.properties && f.properties.colour) || "#E69F00";
      ctx.fillStyle = ctx.strokeStyle;
      ctx.globalAlpha = isDraw ? 0.15 : (f.properties && typeof f.properties.fill_alpha === "number" ? f.properties.fill_alpha : 0.15);
      if (g.type === "Polygon" || g.type === "MultiPolygon") ctx.fill("evenodd");
      else if (g.type !== "LineString") ctx.fill();
      ctx.globalAlpha = 1; ctx.stroke();
    }

    function render() {
      if (disposed) return;
      canvas.setAttribute("data-tool", state.tool);
      ctx.clearRect(0, 0, state.viewW, state.viewH);
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
      if (!state.ready) return;
      state.features.forEach(function (f) { drawFeature(f, false); });
      if (state.drawing) drawFeature(state.drawing, true);
      if (document.activeElement === canvas && state.keyboardCursor) {
        var cursor = toScreen(state.cursor[0], state.cursor[1]);
        ctx.beginPath(); ctx.moveTo(cursor[0]-6,cursor[1]); ctx.lineTo(cursor[0]+6,cursor[1]);
        ctx.moveTo(cursor[0],cursor[1]-6); ctx.lineTo(cursor[0],cursor[1]+6);
        ctx.strokeStyle = "#111"; ctx.lineWidth = 1; ctx.stroke();
      }
    }

    function identity() {
      return state.identity && {entry_id: state.identity.entry_id, revision: state.identity.revision};
    }
    function sameIdentity(a, b) {
      return a && b && a.entry_id === b.entry_id && a.revision === b.revision;
    }
    function shinyInput(suffix, value, origin) {
      if (disposed) return;
      var stamp = origin || identity();
      if (!sameIdentity(stamp, state.identity)) return;
      value = {entry_id: stamp.entry_id, revision: stamp.revision, payload: value};
      if (window.Shiny && el.id) {
        Shiny.setInputValue(el.id + "_" + suffix, value, { priority: "event" });
      }
    }

    function loadImage(uri, cb) {
      if (!uri) { cb(null); return; }
      var im = new Image();
      im.onload = function () { cb(im); };
      im.onerror = function () { cb(null); };
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
    function pointInPolygon(pt, rings) {
      return pointInRing(pt, rings[0]) && !rings.slice(1).some(function (r) { return pointInRing(pt, r); });
    }
    function nearPoint(pt, p) { return Math.hypot(pt[0] - p[0], pt[1] - p[1]) <= 6 / state.zoom; }
    function nearLine(pt, coords) {
      for (var i = 1; i < coords.length; i++) {
        var a = coords[i - 1], b = coords[i], dx = b[0] - a[0], dy = b[1] - a[1];
        var length2 = dx * dx + dy * dy;
        var t = length2 ? Math.max(0, Math.min(1, ((pt[0]-a[0])*dx + (pt[1]-a[1])*dy) / length2)) : 0;
        if (nearPoint(pt, [a[0] + t * dx, a[1] + t * dy])) return true;
      }
      return false;
    }
    // Topmost feature; holes and gaps never select the surrounding polygon.
    function featureAt(ic) {
      for (var k = state.features.length - 1; k >= 0; k--) {
        var properties = state.features[k].properties || {};
        if (properties.visible === false || properties.locked === true) continue;
        var g = state.features[k].geometry, c = g.coordinates;
        if ((g.type === "Polygon" && pointInPolygon(ic, c)) ||
            (g.type === "MultiPolygon" && c.some(function (p) { return pointInPolygon(ic, p); })) ||
            (g.type === "Point" && nearPoint(ic, c)) ||
            (g.type === "MultiPoint" && c.some(function (p) { return nearPoint(ic, p); })) ||
            (g.type === "LineString" && nearLine(ic, c))) return state.features[k];
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
      function shift(c) {
        if (typeof c[0] === "number") return [c[0] + dx, c[1] + dy].concat(c.slice(2));
        return c.map(shift);
      }
      f.geometry.coordinates = shift(f.geometry.coordinates);
    }

    // ---- Pointer interaction ----
    var dragging = false, last = null, polyPts = null, gesture = null, gestureTarget = null;
    function cancelGesture() {
      if (state.editing) state.editing.feature.geometry = state.editing.original;
      dragging = false; last = null; polyPts = null; gesture = null; gestureTarget = null;
      state.drawing = null; state.editing = null;
    }
    function listen(name, callback, options) {
      canvas.addEventListener(name, callback, options);
      listeners.push([name, callback, options]);
    }

    listen("mousedown", function (e) {
      canvas.focus(); state.keyboardCursor = false; render();
      if (!state.ready) return;
      if (state.creationTarget && state.creationTarget.locked && ["point","rect","polygon","freehand","circle"].includes(state.tool)) {
        announce("This layer is locked. Select an unlocked layer to draw."); return;
      }
      var rect = canvas.getBoundingClientRect();
      var sx = e.clientX - rect.left, sy = e.clientY - rect.top;
      var ic = toImageCoords(sx, sy);
      if (!gesture) {
        gesture = identity();
        gestureTarget = state.creationTarget && {layer: state.creationTarget.layer, label: state.creationTarget.label};
      }
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
        if (mh) state.editing = { feature: mh, start: ic, original: JSON.parse(JSON.stringify(mh.geometry)),
          id: mh.properties && mh.properties.roi_id,
          layer: mh.properties && mh.properties.layer,
          label: mh.properties && mh.properties.label };
      }
    });

    listen("mousemove", function (e) {
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

    listen("mouseup", function (e) {
      if (dragging) { dragging = false; gesture = null; gestureTarget = null; canvas.style.cursor = "grab"; emitViewport(); return; }
      if (state.drawing && state.tool === "rect") {
        emitCreated(state.drawing.geometry); state.drawing = null;
      } else if (state.drawing && state.tool === "freehand") {
        emitCreated(state.drawing.geometry); state.drawing = null; polyPts = null;
      } else if (state.drawing && state.tool === "circle") {
        emitCreated(state.drawing.geometry); state.drawing = null;
      } else if (state.editing && state.tool === "edit") {
        var ed = state.editing; state.editing = null;
        if (ed.id) shinyInput("edited", { roi_id: ed.id, layer: ed.layer, label: ed.label, geometry: ed.feature.geometry }, gesture);
      }
      if (!state.drawing) { gesture = null; gestureTarget = null; }
    });

    listen("dblclick", function () {
      if ((state.tool === "polygon") && state.drawing) {
        emitCreated(state.drawing.geometry); state.drawing = null; polyPts = null;
        gesture = null; gestureTarget = null;
      }
    });

    function announce(text) { status.textContent = text; }
    function displayReady(ready, error) {
      state.ready = ready;
      canvas.setAttribute("aria-disabled", String(!ready));
      announce(ready ? "Image ready. Cursor " + state.cursor.join(", ") : error);
      shinyInput("ready", {ready: ready, error: error || null});
    }
    listen("focus", function () { state.keyboardCursor = true; render(); });
    listen("blur", function () { render(); });
    listen("keydown", function (e) {
      if (e.key === "Escape") {
        e.preventDefault(); e.stopPropagation(); cancelGesture(); render(); announce("Drawing cancelled."); return;
      }
      // Shift+Enter belongs to the one global synchronous save/advance action.
      if (e.key === "Enter" && e.shiftKey) return;
      if (!["ArrowLeft","ArrowRight","ArrowUp","ArrowDown","Enter"," "].includes(e.key)) return;
      e.preventDefault(); e.stopPropagation();
      if (!state.ready) return;
      state.keyboardCursor = true;
      var step = e.shiftKey ? 10 : 1;
      if (e.key.indexOf("Arrow") === 0) {
        if (e.key === "ArrowLeft") state.cursor[0] -= step;
        if (e.key === "ArrowRight") state.cursor[0] += step;
        if (e.key === "ArrowUp") state.cursor[1] -= step;
        if (e.key === "ArrowDown") state.cursor[1] += step;
        state.cursor[0] = Math.max(0, Math.min(state.imgW, state.cursor[0]));
        state.cursor[1] = Math.max(0, Math.min(state.imgH, state.cursor[1]));
        if (state.drawing && state.tool === "rect") {
          var a = state.drawing._start, b = state.cursor;
          state.drawing.geometry.coordinates = [[[a[0],a[1]],[b[0],a[1]],[b[0],b[1]],[a[0],b[1]],[a[0],a[1]]]];
        }
        render(); announce("Cursor " + state.cursor.join(", ") + (state.drawing ? "; drawing in progress" : "")); return;
      }
      if (!["point","rect","polygon"].includes(state.tool)) { announce("Choose point, rectangle or polygon for keyboard drawing."); return; }
      if (state.creationTarget && state.creationTarget.locked) { announce("This layer is locked. Select an unlocked layer to draw."); return; }
      if (!gesture) {
        gesture = identity();
        gestureTarget = state.creationTarget && {layer:state.creationTarget.layer,label:state.creationTarget.label};
      }
      var c = state.cursor.slice();
      if (state.tool === "point") {
        emitCreated({type:"Point",coordinates:c}); cancelGesture();
      } else if (state.tool === "rect") {
        if (!state.drawing) state.drawing = {type:"Feature",geometry:{type:"Polygon",coordinates:[[c,c,c,c,c]]},_start:c};
        else {
          var start = state.drawing._start;
          if (start[0] === c[0] || start[1] === c[1]) { announce("Move in both directions before completing a rectangle."); return; }
          emitCreated(state.drawing.geometry); cancelGesture();
        }
      } else {
        if (e.key === "Enter" && polyPts && polyPts.length >= 3) {
          emitCreated({type:"Polygon",coordinates:[polyPts.concat([polyPts[0]])]}); cancelGesture();
        } else {
          polyPts = (polyPts || []).concat([c]);
          state.drawing = {type:"Feature",geometry:{type:"Polygon",coordinates:[polyPts.concat([polyPts[0]])]}};
        }
      }
      render(); announce(state.drawing ? "Anchor placed; drawing in progress." : "Drawing submitted.");
    });

    listen("wheel", function (e) {
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
      if (!state.ready || (state.creationTarget && state.creationTarget.locked)) return;
      var f = { type: "Feature", geometry: geometry, properties: {} };
      state.features.push(f); render();
      if (gestureTarget) f.target = gestureTarget;
      shinyInput("created", f, gesture);
    }
    function emitViewport() {
      shinyInput("viewport", { zoom: state.zoom, center_x: (state.viewW / 2 - state.panX) / state.zoom,
        center_y: (state.viewH / 2 - state.panY) / state.zoom });
    }

    // ---- R -> JS messages and lifecycle ----
    function loadOverlay() {
      var generation = overlayGeneration;
      loadImage(state.overlayUri, function (im) {
        if (disposed || generation !== overlayGeneration) return;
        state.overlayImg = im; render();
      });
    }
    function message(name, m) {
      if (disposed) return;
      if (name === "set_annotations") {
        cancelGesture();
        if (m.identity) state.identity = m.identity;
        state.features = (m.annotations && m.annotations.features) || []; render();
      } else if (name === "set_tool") { cancelGesture(); state.tool = m.tool; render(); }
      else if (name === "set_overlay") {
        ++overlayGeneration;
        state.overlayUri = m.overlay || null;
        state.overlayAlpha = m.alpha; state.overlayImg = null; render();
        loadOverlay();
      } else if (name === "fit_bounds") fitBounds(m.bbox);
      // set_band remains a no-op until a tile source can provide band pixels.
    }
    function dispose() {
      if (disposed) return;
      cancelGesture(); disposed = true; baseGeneration++; overlayGeneration++;
      state.overlayUri = null;
      window.removeEventListener("resize", resize);
      listeners.forEach(function (l) { canvas.removeEventListener(l[0], l[1], l[2]); });
      canvas.remove(); status.remove();
      if (instances[el.id] && instances[el.id].dispose === dispose) delete instances[el.id];
      if (!Object.keys(instances).length && observer) { observer.disconnect(); observer = null; }
    }
    instances[el.id] = {el: el, message: message, dispose: dispose, identity: identity};
    registerDispatcher();
    window.addEventListener("resize", resize);

    return {
      renderValue: function (x) {
        if (disposed) return;
        registerDispatcher();
        // Rendering replaces the annotation objects, so abandon any partial edit.
        cancelGesture();
        var previous = state.identity;
        state.identity = x.identity || {entry_id: el.id, revision: 0};
        state.tool = x.tool || "pan";
        state.creationTarget = x.options && x.options.creationTarget;
        state.imgW = x.tileSource.width;
        state.imgH = x.tileSource.height;
        state.features = (x.annotations && x.annotations.features) || [];
        var uri = x.tileSource.dataUri || null;
        var sourceChanged = uri !== state._lastUri || !previous || previous.entry_id !== state.identity.entry_id;
        var generation = ++baseGeneration;
        ++overlayGeneration;
        if (sourceChanged) {
          state.baseImg = null; state.overlayImg = null; state.overlayUri = null;
          state.ready = false;
          state.cursor = [Math.floor(state.imgW / 2), Math.floor(state.imgH / 2)];
          state._lastUri = uri; resize(); fitBounds(null);
        } else {
          resize();
          // Preserve the latest requested overlay across compatible renders,
          // but let only this render's callback paint it.
          if (state.overlayUri && !state.overlayImg) loadOverlay();
        }
        displayReady(!!state.baseImg, uri ? "Loading image…" :
          (x.tileSource.displayError || "Image display unavailable. Install magick to encode the canvas image, or choose another image."));
        // A pending same-source load is restarted so its callback belongs to this render.
        if (uri && (sourceChanged || !state.baseImg)) {
          loadImage(uri, function (im) {
            if (disposed || generation !== baseGeneration) return;
            state.baseImg = im;
            displayReady(!!im, im ? null : "Image could not be decoded. Choose another image or restore the previous queue.");
            render();
          });
        }
      },
      resize: function () { if (!disposed) resize(); },
      dispose: dispose
    };
  }
});
})();
