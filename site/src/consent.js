// The cookie choice. Google Analytics loads only after Accept, and only on the live site.

const ID = 'G-PHXLHX5G5B';
const LIVE = location.hostname === 'launch-r.web.app';
const KEY = 'launchr-consent';
const $ = (s) => document.querySelector(s);
let running = false;

function saved() {
  try { return localStorage.getItem(KEY); } catch { return null; }
}

function save(value) {
  try { localStorage.setItem(KEY, value); } catch { /* private window: the choice lasts until the page closes */ }
}

function start() {
  if (!LIVE) return;
  window[`ga-disable-${ID}`] = false;
  running = true;
  if (window.gtag) return;
  window.dataLayer = window.dataLayer || [];
  window.gtag = function gtag() { window.dataLayer.push(arguments); };
  window.gtag('js', new Date());
  window.gtag('config', ID);
  const script = document.createElement('script');
  script.async = true;
  script.src = `https://www.googletagmanager.com/gtag/js?id=${ID}`;
  document.head.append(script);
}

function stop() {
  running = false;
  window[`ga-disable-${ID}`] = true;
  document.cookie.split('; ').map((c) => c.split('=')[0]).filter((name) => name.startsWith('_ga')).forEach((name) => {
    [location.hostname, `.${location.hostname}`].forEach((domain) => {
      document.cookie = `${name}=; max-age=0; path=/; domain=${domain}`;
    });
  });
}

function choose(value) {
  save(value);
  if (value === 'yes') start(); else stop();
  $('#notice').hidden = true;
}

/* the only event of our own: it says a zip was built, and nothing about what is in it */
export function countZip() {
  if (running) window.gtag('event', 'zip_built');
}

$('#cookieYes').addEventListener('click', () => choose('yes'));
$('#cookieNo').addEventListener('click', () => choose('no'));
$('#cookieChoice').addEventListener('click', () => { $('#notice').hidden = false; $('#cookieNo').focus(); });

const choice = saved();
if (choice === 'yes') start();
else if (choice !== 'no') $('#notice').hidden = false;
