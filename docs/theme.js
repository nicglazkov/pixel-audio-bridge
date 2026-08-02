// Shared theme toggle. A stored preference wins; otherwise the OS decides and no
// attribute is set, so the page keeps following the system.
(function () {
  var root = document.documentElement, saved = null;
  try { saved = localStorage.getItem("theme"); } catch (e) {}
  if (saved === "light" || saved === "dark") root.setAttribute("data-theme", saved);

  var btn = document.getElementById("theme");
  if (!btn) return;
  btn.addEventListener("click", function () {
    var systemDark = matchMedia("(prefers-color-scheme: dark)").matches;
    var current = root.getAttribute("data-theme") || (systemDark ? "dark" : "light");
    var next = current === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    try { localStorage.setItem("theme", next); } catch (e) {}
  });
})();
