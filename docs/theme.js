// Shared theme toggle. The site is dark unless the reader picks light; the choice is
// remembered. ?theme=light or ?theme=dark in the address overrides it for one visit.
(function () {
  var root = document.documentElement, saved = null;
  var q = location.search.match(/theme=(light|dark)/);
  try { saved = q ? q[1] : localStorage.getItem("theme"); } catch (e) {}
  if (saved === "light" || saved === "dark") root.setAttribute("data-theme", saved);

  var btn = document.getElementById("theme");
  if (!btn) return;
  btn.addEventListener("click", function () {
    var current = root.getAttribute("data-theme") || "dark";
    var next = current === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    try { localStorage.setItem("theme", next); } catch (e) {}
  });
})();
