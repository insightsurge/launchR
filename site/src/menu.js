// The phone menu. The header loads this on every page, so the menu also works on the not-found page.

const $ = (s) => document.querySelector(s);
const root = document.documentElement, menu = $('#menu'), button = $('#menuBtn'), theme = $('#menuTheme');

function show(open) {
  menu.hidden = !open;
  button.setAttribute('aria-expanded', String(open));
}

function followPalette() {
  theme.setAttribute('aria-checked', String(root.dataset.palette === 'ember'));
  $('link[rel="icon"][type="image/svg+xml"]').href = root.dataset.palette === 'ember' ? '/favicon-dark.svg' : '/favicon-light.svg';
}

button.addEventListener('click', () => show(menu.hidden));
menu.addEventListener('click', (e) => { if (e.target.closest('a')) show(false); });
addEventListener('pointerdown', (e) => { if (!menu.hidden && !e.target.closest('#menu, #menuBtn')) show(false); });
addEventListener('keydown', (e) => { if (e.key === 'Escape' && !menu.hidden) { show(false); button.focus(); } });
menu.addEventListener('focusout', (e) => { if (e.relatedTarget && !menu.contains(e.relatedTarget) && e.relatedTarget !== button) show(false); });
matchMedia('(min-width: 768px)').addEventListener('change', (e) => { if (e.matches) show(false); });
theme.addEventListener('click', () => $('#themeBtn').click());

new MutationObserver(followPalette).observe(root, { attributes: true, attributeFilter: ['data-palette'] });
followPalette();
