// Browser intent: capture identity and form values at activation, before Shiny
// counters or a later form edit can reassign the action to another queue entry.
(function () {
  function stamp(name) {
    var displayed = window.atcanvasIdentity && window.atcanvasIdentity("canvas-canvas");
    // Only explicit queue navigation may move beyond a failed/pending display.
    // Every mutation and form selection keeps the canvas's rendered origin,
    // even if the server has already loaded another entry or revision.
    if (/^(queue-(nxt|prev|next_pending)|key_(next|prev|next_pending))$/.test(name))
      return window.annotatRIdentity || displayed;
    return displayed;
  }
  function envelope(name, payload) {
    var origin = stamp(name);
    return origin && {entry_id: origin.entry_id, revision: origin.revision, payload: payload};
  }
  function emit(name, payload) {
    var value = envelope(name, payload);
    if (value && window.Shiny) Shiny.setInputValue(name, value, {priority: "event"});
  }
  function field(id) {
    var el = document.getElementById(id);
    if (!el) return null;
    var radio = el.querySelector && el.querySelector('input[type="radio"]:checked');
    return radio ? radio.value : el.value;
  }
  document.addEventListener("click", function (ev) {
    var button = ev.target.closest && ev.target.closest("[data-at-action]");
    if (!button || button.disabled) return;
    ev.preventDefault(); ev.stopImmediatePropagation();
    var fields = JSON.parse(button.getAttribute("data-at-fields") || "{}"), payload = {};
    Object.keys(fields).forEach(function (key) { payload[key] = field(fields[key]); });
    emit(button.id, payload);
  }, true);
  if (window.jQuery) jQuery(function () {
    Shiny.addCustomMessageHandler("annotatr-state", function (value) {
      window.annotatRIdentity = value;
      document.querySelectorAll('[data-at-action]').forEach(function (button) {
        if (/^(canvas-(undo|redo|copy)|layers-add_|roitable-delete)/.test(button.id)) button.disabled = !value.ready;
      });
    });
    // Let radios retain their normal native selection/focus and Shiny binding.
    // Their separate intent event carries the original label's layer as well.
    jQuery(document).on("shiny:inputchanged", function (ev) {
      if (ev.name !== "layers-layer" && ev.name !== "layers-label") return;
      emit(ev.name + "_intent", {value: ev.value, layer: field("layers-layer")});
    });
  });
  function inControl() {
    var el = document.activeElement;
    if (!el) return false;
    return /^(INPUT|TEXTAREA|SELECT|BUTTON|A)$/.test(el.tagName) || el.isContentEditable;
  }
  var toolKeys = {q:"pan", w:"rect", e:"polygon", r:"freehand", t:"circle", y:"point"};
  document.addEventListener("keydown", function (ev) {
    if (ev.defaultPrevented || inControl() || !window.Shiny) return;
    var k = ev.key, name, value = Date.now();
    if (ev.ctrlKey || ev.metaKey) {
      if (k.toLowerCase() === "z") name = ev.shiftKey ? "key_redo" : "key_undo";
      else if (k.toLowerCase() === "e") name = "key_export";
    } else if (k === "n") name = "key_next";
    else if (k === "p") name = "key_prev";
    else if (k === "N") name = "key_next_pending";
    else if (/^[1-9]$/.test(k)) { name = "key_label"; value = parseInt(k,10); }
    else if (toolKeys[k]) { name = "key_tool"; value = toolKeys[k]; }
    else if (k === "d") name = "key_delete";
    else if (k === "f") name = "key_flag";
    else if (k === "s") name = "key_save";
    else if (k === "?") name = "key_help";
    else if (k === "Enter" && ev.shiftKey) name = "key_commit_advance";
    else if (k === "V" && ev.shiftKey) name = "key_paste_forward";
    if (name) { ev.preventDefault(); emit(name, value); }
  });
})();
