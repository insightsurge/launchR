/* The page: one scroll value drives the picture and the text, and the Start controls open the form. */
import { createHexes } from './hexes.js';

  const root = document.documentElement;
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches || /[?&]still\b/.test(location.search);
  const $ = (s, el) => (el || document).querySelector(s);
  const $$ = (s, el) => [...(el || document).querySelectorAll(s)];
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = (t) => t * t * (3 - 2 * t);
  const store = { get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private window */ } } };
  history.scrollRestoration = 'manual';

  const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  const pal = (low, mid, high, rim, line) => ({ low: hex(low), mid: hex(mid), high: hex(high), rim: hex(rim), line: hex(line) });
  const PALETTES = {
    ember: pal('#4a5fa8', '#a46bb4', '#f6ab85', '#ffd9a6', '#a891d6'),
    paper: pal('#8d93b8', '#8a3d84', '#b5481c', '#c2410c', '#7a5c9c'),
  };
  const design = { ci: 3, hub: 0.27 };
  const scene = createHexes($('#scene'));
  const pages = $$('.page'), hub = $('#launch'), navStart = $('#navStart'), mask = $('#mask'), checkRows = $$('#checkList li');
  const duo = $('#duo'), hexes = $$('.hx');
  const last = pages.length - 1, KIT = pages.indexOf($('#kit')), PLAN = pages.indexOf($('.plans-list').closest('.page'));
  const riskRows = $$('#risk .tree li'), kitRows = $$('#kit .tree li'), planRows = $$('.plans-list li'), QUIET = [KIT, PLAN, pages.indexOf($('#yours'))];
  let slots = [], tops = [], holds = [], stacked = false;

  function placeDuo() {
    if (!stacked) duo.style.height = '';
    const box = duo.getBoundingClientRect();
    const W = box.width, H = box.height;
    const dna = 0;
    let r, centres, g;
    if (stacked) {
      r = Math.min((W - 8) / 1.732, 178);
      centres = [[0, 1.0], [0, -1.0]];
      duo.style.height = `${(4.08 * r + dna + 8).toFixed(0)}px`;
    } else {
      r = Math.min((W - 8) / 3.56, (H - dna - 8) / 2);
      centres = [[-0.89, 0], [0.89, 0]];
    }
    const hh = stacked ? 4.08 * r + dna + 8 : H;
    const shift = dna / 2 / r;
    g = { centres: centres.map(([x, y]) => [x, y - shift]) };
    if (dna) g.dna = { y: (hh / 2 - dna / 2) / r, h: (dna * 0.32) / r, len: Math.min(W, 3.5 * r) / r };
    hexes.forEach((el, i) => {
      el.style.setProperty('--r', `${r.toFixed(1)}px`);
      el.style.left = `${(W / 2 + g.centres[i][0] * r).toFixed(1)}px`;
      el.style.top = `${(hh / 2 - g.centres[i][1] * r).toFixed(1)}px`;
    });
    if (scene) scene.setDuo(last, g);
    return r;
  }

  function measure() {
    stacked = matchMedia('(max-width: 860px), (pointer: coarse) and (max-width: 1100px)').matches;
    const duoR = placeDuo();
    tops = pages.map((p) => p.offsetTop);
    /* on a phone a tall page holds its picture still until its text has scrolled past */
    holds = pages.map((p) => (stacked ? Math.max(0, p.offsetHeight - innerHeight) : 0));
    slots = pages.map((p, i) => {
      const r = $('.slot', p).getBoundingClientRect();
      const rel = r.top + scrollY - p.offsetTop;
      return { cx: r.left + r.width / 2, cy: rel + r.height / 2, bottom: stacked && i === last ? 60 : rel + r.height, S: i === last ? duoR : (Math.min(r.width, r.height) / 2) * 0.8 };
    });
    if (scene && scene.setTree) {
      /* the tree takes all the height it can get, past its slot if the window has room */
      const kit = $('#kit'), sl = slots[KIT], r = $('.slot', kit).getBoundingClientRect();
      scene.setTree(Math.min(((stacked ? r.height : innerHeight - 150) / 2) / (1.24 * sl.S), (r.width / 2) / (0.95 * sl.S)));
    }
  }
  function scrollP(y = scrollY) {
    let i = 0;
    tops.forEach((t, k) => { if (t <= y + 1) i = k; });
    if (i >= last) return last;
    const span = tops[i + 1] - tops[i], hold = Math.min(holds[i], span - 1);
    return i + Math.max(0, y - tops[i] - hold) / (span - hold);
  }
  function stageAt(p) {
    const i = Math.min(last, Math.floor(p)), j = Math.min(last, i + 1), f = smooth(p - i), a = slots[i], b = slots[j];
    const extra = Math.max(0, scrollY - tops[last]);
    return { cx: lerp(a.cx, b.cx, f), cy: lerp(a.cy, b.cy, f) - extra, S: lerp(a.S, b.S, f), bottom: lerp(a.bottom, b.bottom, f) - extra };
  }

  const mouse = { x: -9999, y: -9999, sx: -9999, sy: -9999, nx: 0, ny: 0 };
  const pulse = { v: 0, x: 0, y: 0 };
  let wake = 0, lane = 0, riskHover = -1, rowHover = -1, planHover = -1, P = 0, open = 0, openGoal = 0, yaw = 0, pitch = 0, hot = -1, hubLift = 0, clock = 0, checks = 0, lastT = performance.now();
  function firePulse(x, y) { pulse.v = 0.01; pulse.x = x; pulse.y = y; }

  function draw(dt) {
    const st = stageAt(P), calm = clamp(P - last + 1, 0, 1), t = still ? 4 : clock;
    const rot = 0.7;
    const ty = (mouse.nx * 0.28 + Math.sin(t * 0.2) * 0.1) * rot * (1 - calm * 0.92);
    const tp = (mouse.ny * 0.2 + Math.cos(t * 0.17) * 0.06) * rot * (1 - calm * 0.92);
    yaw += (ty - yaw) * (dt ? Math.min(1, dt * 4) : 1); pitch += (tp - pitch) * (dt ? Math.min(1, dt * 4) : 1);
    hubLift += ((hub.matches(':hover, :focus-visible') ? 1 : 0) - hubLift) * (dt ? Math.min(1, dt * 12) : 1);
    const near = Math.abs(P - design.ci) < 0.3;
    checks = still ? 7 : near ? Math.min(7.6, checks + dt * 3.2) : Math.max(0, checks - dt * 6);
    const pi = Math.min(last, Math.floor(P)), pj = Math.min(last, pi + 1);
    /* hovering the list or the picture lights both */
    const live = !stacked && !open;
    const riskHot = riskHover >= 0 ? riskHover : live && scene && scene.riskRowAt && Math.abs(P - 1) < 0.15 ? scene.riskRowAt(mouse.x, mouse.y, slots[1]) : -1;
    const treeHot = rowHover >= 0 ? rowHover : live && scene && scene.treeRowAt && Math.abs(P - KIT) < 0.15 ? scene.treeRowAt(mouse.x, mouse.y, slots[KIT]) : -1;
    const laneHot = planHover >= 0 ? planHover : live && scene && scene.laneAt && Math.abs(P - PLAN) < 0.15 ? scene.laneAt(mouse.x, mouse.y, slots[PLAN]) : -1;
    const checkHot = hot >= 0 ? hot : live && scene && scene.checkAt && Math.abs(P - design.ci) < 0.15 ? scene.checkAt(mouse.x, mouse.y, slots[design.ci]) : -1;
    checkRows.forEach((row, i) => row.classList.toggle('hot', i === checkHot));
    lane = laneHot >= 0 ? laneHot : scene && scene.laneAt ? -1 : 0;
    riskRows.forEach((row, i) => row.classList.toggle('hot', i === riskHot));
    kitRows.forEach((row, i) => row.classList.toggle('hot', i === treeHot));
    planRows.forEach((row, i) => row.classList.toggle('hot', i === laneHot));
    let rowAt = null;
    const litRow = treeHot >= 0 ? kitRows[treeHot] : riskRows[riskHot];
    if (litRow && !stacked) { const r = litRow.getBoundingClientRect(); rowAt = { x: r.left, y: r.top + r.height / 2 }; }
    if (scene) scene.render({ riskHot, treeHot, laneHot, rowAt, slots, extra: Math.max(0, scrollY - tops[last]), nx: still ? 0 : mouse.nx, ny: still ? 0 : mouse.ny, ax: slots[pi].cx, bx: slots[pj].cx, S0: slots[1].S, bottom: st.bottom, stacked, lane, hexes, hubLift, P, time: t, S: st.S, cx: st.cx, cy: st.cy, mx: still ? -9999 : mouse.sx, my: still ? -9999 : mouse.sy, px: pulse.x, py: pulse.y, pulse: pulse.v, open, yaw, pitch, checks, hot: checkHot });
    checkRows.forEach((row, i) => row.classList.toggle('on', checks > i + 0.9));

    const on = (1 - smooth(clamp(P / 0.24, 0, 1))) * (1 - open);
    const r = design.hub * st.S;
    hub.style.setProperty('--r', `${r.toFixed(1)}px`);
    hub.style.setProperty('--yaw', `${yaw.toFixed(4)}rad`);
    hub.style.setProperty('--pitch', `${(-pitch).toFixed(4)}rad`);
    hub.style.left = `${st.cx.toFixed(1)}px`;
    hub.style.top = `${st.cy.toFixed(1)}px`;
    hub.style.opacity = on.toFixed(3);
    hub.style.visibility = on < 0.02 ? 'hidden' : 'visible';
    hub.style.pointerEvents = on > 0.6 ? 'auto' : 'none';
    hub.tabIndex = on > 0.6 ? 0 : -1;
    navStart.classList.toggle('away', on > 0.02);
    if (stacked) { mask.style.height = `${Math.max(60, st.bottom + 4).toFixed(0)}px`; }
    else pages.forEach((p, i) => {
      const d = clamp(P - i, -1, 1), dir = p.classList.contains('flip') ? 1 : -1, el = $('.text', p);
      el.style.transform = `translateX(${(-d * dir * 70).toFixed(1)}px)`;
      el.style.opacity = (1 - Math.abs(d) * 0.85).toFixed(3);
    });
  }
  function frame(now) {
    const dt = Math.min(0.05, (now - lastT) / 1000);
    lastT = now; clock += dt;
    const goal = scrollP();
    /* the pictures on these pages hold still, so when nothing is happening there is nothing to draw */
    if (goal !== P || pulse.v > 0 || Math.abs(openGoal - open) > 0.001 || !QUIET.includes(P)) wake = now;
    if (now - wake > 1500) { requestAnimationFrame(frame); return; }
    P += (goal - P) * (1 - Math.exp(-dt * 8));
    if (Math.abs(goal - P) < 0.0004) P = goal;
    open += (openGoal - open) * (1 - Math.exp(-dt * 5));
    if (Math.abs(openGoal - open) < 0.001) open = openGoal;
    mouse.sx += (mouse.x - mouse.sx) * 0.25; mouse.sy += (mouse.y - mouse.sy) * 0.25;
    if (pulse.v > 0) pulse.v = pulse.v >= 1 ? 0 : Math.min(1, pulse.v + dt * 0.85);
    draw(dt);
    requestAnimationFrame(frame);
  }
  const drawStill = () => { P = scrollP(); draw(0); };

  ['pointermove', 'pointerdown', 'keydown', 'focusin', 'click'].forEach((type) => addEventListener(type, () => { wake = performance.now(); }, { passive: true }));
  addEventListener('pointermove', (e) => { mouse.x = e.clientX; mouse.y = e.clientY; mouse.nx = (e.clientX / innerWidth) * 2 - 1; mouse.ny = 1 - (e.clientY / innerHeight) * 2; }, { passive: true });
  addEventListener('pointerup', (e) => { if (e.pointerType === 'touch') mouse.x = mouse.y = -9999; });
  addEventListener('pointerdown', (e) => { if (e.target.closest('dialog, .notice')) return; mouse.sx = mouse.x = e.clientX; mouse.sy = mouse.y = e.clientY; });
  addEventListener('scroll', () => { if (still) drawStill(); }, { passive: true });
  let timer = 0;
  addEventListener('resize', () => { clearTimeout(timer); timer = setTimeout(() => { if (scene) scene.resize(); measure(); if (still) drawStill(); }, 80); });

  ['pointerenter', 'pointerleave', 'focus', 'blur'].forEach((type) => hub.addEventListener(type, () => { if (still) draw(0); }));
  const hoverable = (rows, set) => rows.forEach((li, i) => {
    li.tabIndex = 0;
    const put = (v) => { set(v); if (still) draw(0); };
    li.addEventListener('pointerenter', (e) => { if (e.pointerType === 'mouse') put(i); });
    li.addEventListener('pointerleave', (e) => { if (e.pointerType === 'mouse') put(-1); });
    li.addEventListener('focus', () => { if (li.matches(':focus-visible')) put(i); });
    li.addEventListener('blur', () => put(-1));
    /* no hover on a phone: a tap lights the row, and a second tap clears it */
    li.addEventListener('click', () => { if (stacked) put(li.classList.contains('hot') ? -1 : i); });
  });
  hoverable(planRows, (v) => { planHover = v; });
  hoverable(kitRows, (v) => { rowHover = v; });
  hoverable(riskRows, (v) => { riskHover = v; });
  hoverable(checkRows, (v) => { hot = v; });

  /* ---------- the form ---------- */
  const dialog = $('#setup');
  const routes = { a: ['After public', 'Before CRAN', 'After acceptance', 'Next release'], b: ['After public', 'Next release'], c: ['Before public', 'After public', 'Before CRAN', 'After acceptance', 'Next release'], d: [] };
  const releases = { a: 'Yes, up to CRAN and after', b: 'Yes, for GitHub or R-universe', c: 'Held until you go public', d: 'None. It stays private.' };
  const names = { a: 'Public, going to CRAN', b: 'Public, not for CRAN', c: 'Private for now, public and CRAN later', d: 'Private for good' };
  const hues = { a: '--c1', b: '--c2', c: '--c3', d: '--c4' };
  function showPlan(plan, bump) {
    $('#pvLists').innerHTML = routes[plan].length ? routes[plan].map((s, i) => `<li style="animation-delay:${i * 50}ms">${s}</li>`).join('') : '<li class="none">None, no release features</li>';
    $('#pvRelease').textContent = releases[plan];
    $('#pvPlan').textContent = names[plan];
    const h = $('#pvHex');
    h.style.setProperty('--pc', `var(${hues[plan]})`);
    if (bump) { h.classList.remove('bump'); void h.offsetWidth; h.classList.add('bump'); }
  }
  function showName() {
    const v = $('#pkg').value.trim() || 'fooBarPkg';
    $('#pvName').textContent = v; $('#dlName').textContent = v;
    const m = v.match(/^(.)(?:.*?([A-Z]))?/);
    $('#pvLetter').textContent = m ? m[1] + (m[2] || v[1] || '') : 'R';
  }
  $('#plans').addEventListener('change', (e) => showPlan(e.target.value, true));
  $('#pkg').addEventListener('input', showName);
  let origin = { x: innerWidth / 2, y: innerHeight / 2 };
  const reach = () => Math.hypot(Math.max(origin.x, innerWidth - origin.x), Math.max(origin.y, innerHeight - origin.y)) + 20;
  const grow = (back) => {
    const a = `circle(0px at ${origin.x}px ${origin.y}px)`, b = `circle(${reach()}px at ${origin.x}px ${origin.y}px)`;
    return dialog.animate({ clipPath: back ? [b, a] : [a, b] }, { duration: still ? 0 : 620, easing: 'cubic-bezier(0.22, 1, 0.36, 1)', fill: 'both' });
  };
  let closing = false;
  let opener = hub;
  function openForm(from) {
    opener = from;
    const r = from.getBoundingClientRect();
    origin = { x: r.left + r.width / 2, y: r.top + r.height / 2 };
    if (from === hub) firePulse(origin.x, origin.y);
    dialog.showModal(); root.classList.add('locked'); openGoal = 1; if (still) open = 1;
    showName(); showPlan($('input[name=plan]:checked').value, false); grow(false);
  }
  [hub, navStart, $('#endStart'), $('#existingStart')].forEach((from) => from.addEventListener('click', () => openForm(from)));
  async function closeForm() {
    if (closing) return;
    closing = true; openGoal = 0; if (still) open = 0;
    await grow(true).finished;
    dialog.close(); root.classList.remove('locked'); closing = false;
    opener.focus({ preventScroll: true }); if (still) draw(0);
  }
  $('#close').addEventListener('click', closeForm);
  dialog.addEventListener('cancel', (e) => { e.preventDefault(); closeForm(); });
  dialog.addEventListener('close', () => root.classList.remove('locked'));
  $('#noticeClose').addEventListener('click', () => { $('#notice').hidden = true; });

  /* ---------- light and dark: follows the system until the visitor chooses ---------- */
  const themeBtn = $('#themeBtn'), system = matchMedia('(prefers-color-scheme: dark)');
  const systemPalette = () => (system.matches ? 'ember' : 'paper');
  function apply(palette) {
    root.dataset.palette = palette;
    themeBtn.setAttribute('aria-label', `Switch to ${palette === 'ember' ? 'light' : 'dark'} mode`);
    if (scene) scene.setPalette(PALETTES[palette], () => { wake = performance.now(); if (still && slots.length) draw(0); });
    wake = performance.now();
    if (still && slots.length) draw(0);
  }
  themeBtn.addEventListener('click', () => {
    const next = root.dataset.palette === 'ember' ? 'paper' : 'ember';
    store.set('launchr-theme', next === systemPalette() ? '' : next);
    apply(next);
  });
  system.addEventListener('change', () => { if (!store.get('launchr-theme')) apply(systemPalette()); });
  apply(root.dataset.palette);

  measure();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => { measure(); if (still) drawStill(); });
  addEventListener('load', () => { measure(); if (still) drawStill(); });
  P = scrollP();
  if (still) drawStill(); else requestAnimationFrame((t) => { lastT = t; frame(t); });
  if (import.meta.env.DEV) window.__launchr = { snap(on) { root.style.scrollSnapType = on ? '' : 'none'; }, get P() { return P; }, jump(n = 0) { P = scrollP(); draw(0); for (let i = 0; i < n; i += 1) draw(0.1); } };
