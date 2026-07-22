// Keyboard shortcuts for annotatR. Bindings never fire while a text input,
// textarea, or select has focus.
(function () {
  function inTextField() {
    var el = document.activeElement;
    if (!el) return false;
    var tag = el.tagName;
    return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" ||
      el.isContentEditable;
  }

  // key -> Shiny input value to set (as an event).
  var toolKeys = { q: "pan", w: "rect", e: "polygon", r: "freehand", t: "circle", y: "point" };

  document.addEventListener("keydown", function (ev) {
    if (inTextField()) return;
    if (!window.Shiny) return;
    var k = ev.key;

    // Modifier combos first, so e.g. Ctrl+E is never swallowed by the "e" tool
    // key. Any other Ctrl/Meta chord is left to the browser.
    if (ev.ctrlKey || ev.metaKey) {
      if (k.toLowerCase() === "z") {
        Shiny.setInputValue(ev.shiftKey ? "key_redo" : "key_undo", Date.now(), { priority: "event" });
      } else if (k.toLowerCase() === "e") {
        ev.preventDefault();
        Shiny.setInputValue("key_export", Date.now(), { priority: "event" });
      }
      return;
    }

    if (k === "n") Shiny.setInputValue("key_next", Date.now(), { priority: "event" });
    else if (k === "p") Shiny.setInputValue("key_prev", Date.now(), { priority: "event" });
    else if (k === "N") Shiny.setInputValue("key_next_pending", Date.now(), { priority: "event" });
    else if (/^[1-9]$/.test(k)) Shiny.setInputValue("key_label", parseInt(k, 10), { priority: "event" });
    else if (toolKeys[k]) Shiny.setInputValue("key_tool", toolKeys[k], { priority: "event" });
    else if (k === "d") Shiny.setInputValue("key_delete", Date.now(), { priority: "event" });
    else if (k === "f") Shiny.setInputValue("key_flag", Date.now(), { priority: "event" });
    else if (k === "s") { ev.preventDefault(); Shiny.setInputValue("key_save", Date.now(), { priority: "event" }); }
    else if (k === "?") Shiny.setInputValue("key_help", Date.now(), { priority: "event" });
    else if (k === "Enter" && ev.shiftKey) { ev.preventDefault(); Shiny.setInputValue("key_commit_advance", Date.now(), { priority: "event" }); }
    else if (k === "V" && ev.shiftKey) Shiny.setInputValue("key_paste_forward", Date.now(), { priority: "event" });
  });
})();
