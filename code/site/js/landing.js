// DocMD landing — behaviour only. Keep this the single home for page scripts.
//
// Separation of concerns (see code/site/README.md):
//   structure -> index.html   presentation -> css/landing.css   behaviour -> here
// Do NOT move this logic back into an inline <script> in index.html, and do not
// add inline `onclick=`/`style=` attributes. New behaviour goes in this file.

(function () {
  var root = document.documentElement;

  // Theme toggle: persist the manual choice; otherwise the CSS follows the OS
  // via prefers-color-scheme.
  var toggle = document.getElementById('themeToggle');
  try {
    var saved = localStorage.getItem('docmd-theme');
    if (saved) root.setAttribute('data-theme', saved);
  } catch (e) {}

  function currentTheme() {
    return (
      root.getAttribute('data-theme') ||
      (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
    );
  }

  if (toggle) {
    toggle.addEventListener('click', function () {
      var next = currentTheme() === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      try {
        localStorage.setItem('docmd-theme', next);
      } catch (e) {}
    });
  }

  // Copy-to-clipboard for the install/command blocks.
  document.querySelectorAll('.copy').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var text = btn.getAttribute('data-copy');
      if (!text || !navigator.clipboard) return;
      navigator.clipboard.writeText(text).then(function () {
        btn.textContent = '✓';
        btn.classList.add('done');
        setTimeout(function () {
          btn.textContent = '⧉';
          btn.classList.remove('done');
        }, 1400);
      });
    });
  });
})();
