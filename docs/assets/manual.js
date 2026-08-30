// Filter the table of contents. There is no search index and no fetch: the
// whole nav is already in the DOM, so matching titles is the entire feature.
(function () {
  var box = document.getElementById('filter');
  if (!box) return;
  var items = Array.prototype.slice.call(document.querySelectorAll('.toc li'));

  box.addEventListener('input', function () {
    var q = box.value.trim().toLowerCase();
    items.forEach(function (li) {
      li.hidden = q !== '' && li.textContent.toLowerCase().indexOf(q) === -1;
    });
  });

  // "/" focuses the box, Escape clears it -- the hint next to the box.
  document.addEventListener('keydown', function (e) {
    if (e.key === '/' && document.activeElement !== box) {
      e.preventDefault();
      box.focus();
    } else if (e.key === 'Escape' && document.activeElement === box) {
      box.value = '';
      box.dispatchEvent(new Event('input'));
      box.blur();
    }
  });
})();
