// Shared theme toggle. The inline script in each <head> applies ?theme=light|dark (one
// visit), then a saved choice, then the system setting, before first paint. This file wires
// the button and, until the reader picks a theme, follows the system setting when it changes.
(function () {
  var KEY = "theme";
  var root = document.documentElement;

  function picked() {
    if (/theme=(light|dark)/.test(location.search)) return true;
    try { var s = localStorage.getItem(KEY); return s === "light" || s === "dark"; } catch (e) { return false; }
  }

  var mq = window.matchMedia && window.matchMedia("(prefers-color-scheme: light)");
  if (mq && mq.addEventListener) {
    mq.addEventListener("change", function (e) {
      if (!picked()) root.setAttribute("data-theme", e.matches ? "light" : "dark");
    });
  }

  var btn = document.getElementById("theme");
  if (!btn) return;
  btn.addEventListener("click", function () {
    var next = root.getAttribute("data-theme") === "light" ? "dark" : "light";
    root.setAttribute("data-theme", next);
    try { localStorage.setItem(KEY, next); } catch (e) {}
  });
})();
