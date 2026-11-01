/* Nineteen whole hexagons, one for each file, and seven more for the checks. Each has a place, tilt and size on every page,
   and the scroll carries it from one to the next. Nothing breaks up. Nothing here draws text. */
  const TAU = Math.PI * 2, PI = Math.PI, S3 = Math.sqrt(3), BASE = 19, N = 26, SPR = 200, BIG = 420;
  const c01 = (x) => Math.min(1, Math.max(0, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const sstep = (a, b, x) => { const t = c01((x - a) / (b - a)); return t * t * (3 - 2 * t); };
  function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
  const corner = (i) => PI / 6 + (i * PI) / 3;

  /* ---------- where every hexagon sits on every page, in the page's own units ---------- */
  const CELLS = [[0, 0], [1, 0], [0, 1], [-1, 1], [-1, 0], [0, -1], [1, -1], [2, 0], [1, 1], [0, 2], [-1, 2], [-2, 2], [-2, 1], [-2, 0], [-1, -1], [0, -2], [1, -2], [2, -2], [2, -1]];
  const comb = (side, turn = 0) => CELLS.map(([q, r]) => {
    const x = side * S3 * (q + r / 2), y = side * 1.5 * r, c = Math.cos(turn), s = Math.sin(turn);
    return { x: x * c - y * s, y: x * s + y * c, r: side, rot: turn, a: 1 };
  });
  /* page 2: the four files a package starts with stay in the pattern; the rest leave gaps */
  const HAS = 4;
    const gapped = () => comb(0.27).map((c, k) => ({ ...c, r: k < HAS ? c.r * 0.86 : c.r, a: k < HAS ? 1 : 0 }));
  function hubs() {
    const out = [{ x: 0, y: 0, r: 0.3, rot: 0, a: 1 }];
    for (let i = 1; i < BASE; i += 1) { const a = PI / 2 - ((i - 0.5) * TAU) / 18; out.push({ x: Math.cos(a) * 1.05, y: Math.sin(a) * 1.05, r: 0.07, rot: 0, a: 0.9 }); }
    for (let i = 0; i < 7; i += 1) { const a = PI / 2 - (i * TAU) / 7; out.push({ x: Math.cos(a) * 0.68, y: Math.sin(a) * 0.68, r: 0.15, rot: 0, a: 1 }); }
    return out;
  }
  /* page 3: the package tree. One hexagon per file, level with its row of the list when rows are
     given; the workflows row is three rows tall and its line carries the seven checks. */
  const FILES = [['rfolder', 0], ['man', 0], ['description', 0], ['namespace', 0], ['readme', 0], ['tests', 1], ['flows', 2], ['lintr', 3], ['air', 3], ['licence', 4], ['news', 5], ['cran', 5], ['buildignore', 6], ['gitignore', 6], ['contributing', 7], ['security', 7], ['issues', 8], ['pr', 9], ['labels', 10]];
  const CHECKS = ['check', 'lint', 'secret', 'cover', 'none', 'full', 'week'], FLOW = 6, TRUNK = -0.9;
  /* page 5: which hexagons sit on each plan's path */
  const LANE_K = [[], [], [], []];
  function tree(z) {
    const u = (2.48 / 13) * z, ys = [0, 1, 3, 5, 6, 7, 8, 9, 10, 11, 12].map((n, i) => 1.24 * z - u * (i === 2 ? 3.5 : n + 0.5));
    const r = u * 0.46, out = [], used = {};
    FILES.forEach(([, row], k) => { const j = used[row] || 0; used[row] = j + 1; out[k] = { x: (-0.72 + j * 0.27) * z, y: ys[row], r, rot: 0, a: 1, row }; });
    const p = out[FLOW];
    for (let j = 0; j < 7; j += 1) out[BASE + j] = { x: (-0.46 + j * 0.195) * z, y: p.y + (j % 2 ? -u : u) * 0.98, r, rot: 0, a: 1, row: 2 };
    return out;
  }
  const rimOwner = (i) => BASE + (Math.round((i - 0.5) * (7 / 18) - 0.5) % 7);
  const hidden = (at) => [...Array(7)].map(() => ({ x: at.x, y: at.y, r: 0, rot: 0, a: 1 }));
  const LX = [-0.84, -0.28, 0.28, 0.84], MARKS = [[1, 2, 3, 4], [1, 4], [0, 1, 2, 3, 4], [2]], END = 13;
  /* page 5 keeps its hexagons small, so the four paths stay the picture */
  function paths() {
    const out = [{ x: 0, y: -1.02, r: 0.17, rot: 0, a: 1 }];
    MARKS.forEach((m, n) => m.forEach((v) => { LANE_K[n].push(out.length); out.push({ x: LX[n], y: -0.42 + v * 0.21, r: 0.095, rot: 0, a: 1 }); }));
    out.push({ x: 0, y: 1.02, r: 0.17, rot: 0, a: 1 });
    while (out.length < N) out.push({ x: out[0].x, y: out[0].y, r: 0, rot: 0, a: 1 });
    return out;
  }
  const budOf = (j, f) => c01((sstep(0.72, 1, f) - j * 0.07) / (1 - 6 * 0.07));
  const open = (y) => sstep(-1.1, -0.6, y) * (1 - sstep(0.62, 1.12, y));
  function lastPage(centres) {
    return CELLS.map((_, k) => {
      if (k < 2) return { x: centres[k][0], y: centres[k][1], r: 1, rot: 0, a: 1 };
      const c = centres[k % 2], a = corner(k);
      return { x: c[0] + Math.cos(a), y: c[1] + Math.sin(a), r: 0.05, rot: 0, a: 0 };
    });
  }

  /* ---------- the hexagons themselves: three kinds, in dots, drawn once ---------- */
  const poly = (g, pts, close) => { g.beginPath(); pts.forEach((p, i) => g[i ? 'lineTo' : 'moveTo'](p[0], p[1])); if (close) g.closePath(); g.stroke(); };
  const circle = (g, x, y, r, a = 0, b = TAU) => { g.beginPath(); g.arc(x, y, r, a, b); g.stroke(); };
  const dot = (g, x, y, r) => { g.beginPath(); g.arc(x, y, r, 0, TAU); g.fill(); };
  const SYMBOLS = {
    rfolder(g) { poly(g, [[-72, -52], [28, -52]]); poly(g, [[-34, 0], [72, 0]]); poly(g, [[-72, 52], [8, 52]]); },
    man(g) { poly(g, [[0, -52], [0, 72]]); poly(g, [[0, -52], [-86, -76], [-86, 46], [0, 72], [86, 46], [86, -76]], true); },
    description(g) { g.strokeRect(-88, -62, 176, 124); circle(g, -44, -12, 20); poly(g, [[8, -24], [60, -24]]); poly(g, [[8, 6], [60, 6]]); poly(g, [[-62, 34], [60, 34]]); },
    namespace(g) { poly(g, [[22, -72], [-72, -72], [-72, 72], [22, 72]]); poly(g, [[-18, 0], [88, 0]]); poly(g, [[54, -34], [88, 0], [54, 34]]); },
    readme(g) { poly(g, [[-56, -86], [24, -86], [60, -50], [60, 86], [-56, 86]], true); poly(g, [[24, -86], [24, -50], [60, -50]]); poly(g, [[-28, -6], [32, -6]]); poly(g, [[-28, 36], [32, 36]]); },
    tests(g) { circle(g, 0, 0, 84); poly(g, [[-42, 2], [-10, 36], [46, -36]]); },
    flows(g) { circle(g, 0, 0, 78, 0.5, TAU - 0.15); poly(g, [[56, 14], [78, 44], [98, 10]]); },
    lintr(g) { g.strokeRect(-92, -30, 184, 60); for (let x = -60; x <= 60; x += 30) poly(g, [[x, -30], [x, x % 60 ? -8 : 2]]); },
    air(g) { g.beginPath(); g.moveTo(-88, -24); g.lineTo(38, -24); g.arc(38, -48, 24, PI / 2, -PI * 0.9, true); g.stroke(); g.beginPath(); g.moveTo(-88, 22); g.lineTo(58, 22); g.arc(58, 46, 24, -PI / 2, PI * 0.9); g.stroke(); poly(g, [[-62, 0], [-10, 0]]); },
    licence(g) { circle(g, 0, -22, 50); poly(g, [[-30, 18], [-46, 88], [0, 62], [46, 88], [30, 18]]); },
    news(g) { poly(g, [[-80, -24], [-30, -24], [62, -72], [62, 72], [-30, 24], [-80, 24]], true); poly(g, [[-46, 24], [-28, 76]]); poly(g, [[86, -18], [86, 18]]); },
    cran(g) { poly(g, [[-88, -62], [88, -62], [88, 36], [-8, 36], [-50, 78], [-50, 36], [-88, 36]], true); [-40, 0, 40].forEach((x) => dot(g, x, -13, 10)); },
    buildignore(g) { poly(g, [[-88, -72], [88, -72], [20, 8], [20, 62], [-20, 84], [-20, 8]], true); },
    gitignore(g) { g.beginPath(); g.moveTo(-90, 0); g.quadraticCurveTo(0, -84, 90, 0); g.quadraticCurveTo(0, 84, -90, 0); g.stroke(); circle(g, 0, 0, 22); poly(g, [[-72, -72], [72, 72]]); },
    contributing(g) { circle(g, -38, -34, 27); circle(g, -38, 66, 56, PI + 0.15, TAU - 0.15); circle(g, 44, -34, 27); circle(g, 44, 66, 56, PI + 0.5, TAU - 0.15); },
    security(g) { poly(g, [[0, -90], [78, -58], [78, 14], [0, 90], [-78, 14], [-78, -58]], true); },
    issues(g) { g.strokeRect(-64, -66, 128, 152); g.strokeRect(-28, -86, 56, 34); poly(g, [[-36, -12], [36, -12]]); poly(g, [[-36, 32], [36, 32]]); },
    pr(g) { circle(g, -50, -72, 18); circle(g, -50, 72, 18); circle(g, 56, -28, 18); poly(g, [[-50, -54], [-50, 54]]); g.beginPath(); g.moveTo(56, -10); g.quadraticCurveTo(56, 34, -50, 42); g.stroke(); },
    labels(g) { poly(g, [[-86, -72], [14, -72], [88, 2], [10, 80], [-86, -18]], true); circle(g, -46, -36, 14); },
    check(g) { circle(g, -16, -16, 56); poly(g, [[26, 26], [80, 80]]); },
    lint(g) { const p = []; for (let x = -86; x <= 86; x += 6) p.push([x, -30 + Math.sin(x / 15) * 22]); poly(g, p); poly(g, [[-86, 44], [86, 44]]); },
    secret(g) { g.strokeRect(-62, -8, 124, 88); circle(g, 0, -8, 42, PI, TAU); },
    cover(g) { g.save(); g.globalAlpha *= 0.3; circle(g, 0, 0, 78); g.restore(); g.lineWidth *= 1.5; circle(g, 0, 0, 78, -PI / 2, PI); },
    none(g) { circle(g, 0, 0, 80); poly(g, [[-57, -57], [57, 57]]); },
    full(g) { poly(g, [[-92, 6], [-58, 42], [2, -34]]); poly(g, [[-26, 6], [8, 42], [68, -34]]); },
    week(g) { g.strokeRect(-76, -66, 152, 142); poly(g, [[-76, -24], [76, -24]]); for (let i = 0; i < 7; i += 1) dot(g, -48 + (i % 4) * 32, 8 + Math.floor(i / 4) * 32, 8); },
  };
  function sprite(pal, kind, size, symbol) {
    const R = rng(11 + kind), cv = document.createElement('canvas'), w = Math.ceil(size * 2.2);
    cv.width = cv.height = w;
    const g = cv.getContext('2d'), o = w / 2;
    const ramp = (t) => { const f = t < 0.5 ? t * 2 : t * 2 - 1, a = t < 0.5 ? pal.low : pal.mid, b = t < 0.5 ? pal.mid : pal.high; return `rgb(${a.map((v, i) => Math.round(lerp(v, b[i], f) * 255)).join(',')})`; };
    const vtx = (i, r) => [Math.cos(corner(i)) * r, Math.sin(corner(i)) * r];
    const unit = size / 200;
    const dots = (n, at, tone, rad = 3.4) => { for (let i = 0; i < n; i += 1) { const p = at(); g.fillStyle = ramp(c01(tone + (R() - 0.5) * 0.16)); g.globalAlpha = 0.6 + R() * 0.4; g.beginPath(); g.arc(o + p[0], o + p[1], rad * (size > 300 ? 0.62 : unit) * (0.6 + R() * 0.7), 0, TAU); g.fill(); } };
    const onHex = (r, j) => () => { const e = Math.floor(R() * 6), a = vtx(e, r), b = vtx(e + 1, r), t = R(); return [lerp(a[0], b[0], t) + (R() - 0.5) * j, lerp(a[1], b[1], t) + (R() - 0.5) * j]; };
    const inDisc = (r) => () => { const a = R() * TAU, d = Math.sqrt(R()) * r; return [Math.cos(a) * d, Math.sin(a) * d]; };
    const tone = [0.86, 0.56, 0.42, 0.95, 0.9, 0.72][kind];
    g.beginPath(); for (let i = 0; i <= 6; i += 1) { const v = vtx(i, size); g[i ? 'lineTo' : 'moveTo'](o + v[0], o + v[1]); }
    g.strokeStyle = ramp(Math.max(tone, 0.6)); g.globalAlpha = 0.55; g.lineWidth = size > 300 ? 2.4 : 5 * unit; g.lineJoin = 'round'; g.stroke();
    dots(size > 300 ? 5200 : 1300, onHex(size, size * 0.03), Math.max(tone, 0.55));
    if (kind === 0) { dots(700, onHex(size * 0.7, size * 0.02), tone * 0.9); dots(1800, inDisc(size * 0.6), tone * 0.6, 2.4); }
    if (kind === 1) dots(600, () => { const a = R() * TAU, r = size * (0.5 + (R() - 0.5) * 0.04); return [Math.cos(a) * r, Math.sin(a) * r]; }, tone);
    if (kind === 2) dots(600, () => { const e = Math.floor(R() * 3) * 2, a = vtx(e, size * 0.72), b = vtx(e + 1, size * 0.72), t = 0.18 + R() * 0.64; return [lerp(a[0], b[0], t), lerp(a[1], b[1], t)]; }, tone);
    g.globalAlpha = 1;
    if (symbol) {
      /* the symbol is laid down in the same dots as the hexagon, along a slightly unsteady line */
      const m = document.createElement('canvas'); m.width = m.height = w;
      const q = m.getContext('2d', { willReadFrequently: true });
      q.translate(o, o); q.lineWidth = 15; q.lineCap = 'round'; q.lineJoin = 'round'; SYMBOLS[symbol](q);
      const px = q.getImageData(0, 0, w, w).data, s1 = R() * TAU, s2 = R() * TAU;
      for (let y = 0; y < w; y += 2) for (let x = 0; x < w; x += 2) {
        if (R() > (px[(y * w + x) * 4 + 3] / 255) * 0.62) continue;
        g.fillStyle = ramp(c01(tone + 0.1 + (R() - 0.5) * 0.14)); g.globalAlpha = 0.75 + R() * 0.25;
        g.beginPath(); g.arc(x + Math.sin(y / 23 + s1) * 3.5 + (R() - 0.5) * 3, y + Math.sin(x / 29 + s2) * 3.5 + (R() - 0.5) * 3, 2.3 + R() * 1.4, 0, TAU); g.fill();
      }
      g.globalAlpha = 1;
    }
    return cv;
  }

  export function createHexes(canvas) {
    const ctx = canvas.getContext('2d');
    let W = 1, H = 1, dpr = 1, treeZ = 1, job = 0, S = [], art = {}, rimSpr = null, centreSpr = null, css = null;
    const made = new Map();
    const withHidden = (list, at) => list.concat(hidden(at));
    const pages = [withHidden(comb(0.27), { x: 0, y: 0 }), withHidden(gapped(), { x: 0, y: 0 }), tree(1), hubs(), null, null, null];
    pages[4] = paths();
    pages[5] = withHidden(comb(0.115, PI / 6), { x: 0, y: 0 });
    pages[6] = withHidden(lastPage([[-0.89, 0], [0.89, 0]]), { x: 0, y: 0 });
    const LINKS = [];
    for (let i = 0; i < 7; i += 1) LINKS.push([0, BASE + i, i]);
    for (let i = 1; i < BASE; i += 1) LINKS.push([rimOwner(i), i, -1]);
    function resize() { dpr = Math.min(devicePixelRatio || 1, 2); W = innerWidth; H = innerHeight; canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr); }
    function line(pts, col, a, w) {
      if (a < 0.01 || pts.length < 2) return;
      ctx.beginPath(); pts.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])));
      ctx.globalAlpha = a; ctx.strokeStyle = col; ctx.lineWidth = w; ctx.stroke(); ctx.globalAlpha = 1;
    }
    const part = (pts, f) => {
      const lens = pts.slice(1).map((p, i) => Math.hypot(p[0] - pts[i][0], p[1] - pts[i][1]));
      let want = lens.reduce((a, b) => a + b, 0) * c01(f); const out = [pts[0]];
      for (let i = 0; i < lens.length && want > 0; i += 1) { const t = Math.min(1, want / (lens[i] || 1)); out.push([lerp(pts[i][0], pts[i + 1][0], t), lerp(pts[i][1], pts[i + 1][1], t)]); want -= lens[i]; }
      return out;
    };
    const ring = (x, y, r, turn = 0) => [0, 1, 2, 3, 4, 5, 6].map((i) => [x + Math.cos(corner(i) + turn) * r, y + Math.sin(corner(i) + turn) * r]);

    function render(s) {
      const P = s.P, t = s.time;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, W, H);
      ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      if (!S.length || s.open > 0.98) return;
      const last = pages.length - 1, i = Math.min(last, Math.floor(P)), j = Math.min(last, i + 1), f = P - i;
      const at = (page, n, p) => { const sl = s.slots[n]; return { X: sl.cx + p.x * sl.S, Y: sl.cy - p.y * sl.S - (n === last ? s.extra : 0), r: p.r * sl.S, rot: p.rot, a: p.a }; };
      const grow = sstep(5.55, 5.95, P);
      const now = pages[0].map((_, k) => {
        const a = at(pages[i], i, pages[i][k]), b = at(pages[j], j, pages[j][k]);
        /* into the tree: the files arrive first, then the checks slide along the line and step onto their branches */
        if (i === 1 && k >= BASE) {
          const p = at(pages[2], 2, pages[2][FLOW]), e = budOf(k - BASE, f), along = sstep(0, 0.65, e), step = sstep(0.55, 1, e);
          return { x: lerp(p.X, b.X, along), y: lerp(p.Y, b.Y, step), r: b.r * sstep(0, 0.4, e), rot: 0, a: (1 - s.open), push: 0, e };
        }
        const d = (k / (N - 1)) * 0.3, e = i === j ? 0 : sstep(d, d + 0.7, i === 1 ? c01(f / 0.72) : f), side = k % 2 ? 1 : -1, arc = Math.sin(PI * e);
        const dx = b.X - a.X, dy = b.Y - a.Y;
        let x = lerp(a.X, b.X, e) - dy * arc * 0.13 * side, y = lerp(a.Y, b.Y, e) + dx * arc * 0.13 * side;
        /* the tree, the paths and the package hold still, so hexagons stay on their lines */
        const still = (1 - grow) * (1 - sstep(0.6, 0.9, P) * (1 - sstep(1.1, 1.4, P))) * (1 - sstep(1.6, 1.9, P) * (1 - sstep(2.1, 2.4, P))) * (1 - sstep(3.6, 3.9, P) * (1 - sstep(5.1, 5.4, P)));
        x += (Math.sin(t * 0.5 + k * 1.7) * 2.2 + s.nx * (3 + (k % 3) * 3)) * still;
        y += (Math.cos(t * 0.43 + k * 2.3) * 2.2 - s.ny * (2 + (k % 3) * 2)) * still;
        const mx = x - s.mx, my = y - s.my, md = Math.hypot(mx, my) || 1, push = k ? sstep(120, 0, md) * still : 0;
        x += (mx / md) * push * 12; y += (my / md) * push * 12;
        const cx = s.cx; x = cx + (x - cx) * (1 + s.open * 0.7); y = s.cy + (y - s.cy) * (1 + s.open * 0.7);
        return { x, y, r: lerp(a.r, b.r, e), rot: lerp(a.rot, b.rot, e) + arc * 0.4 * side, a: lerp(a.a, b.a, e) * (1 - s.open), push, e };
      });
      const shown = 1 - s.open;

      /* page 2: dashed outlines mark what is missing, and the next page fills them */
      const gaps = sstep(0.4, 0.9, P) * (1 - sstep(1, 1.3, P)) * shown, hotRisk = Math.abs(P - 1) < 0.3 && s.riskHot === 0 ? 0 : -1;
      const spot = (k) => { if (P < 1) return now[k]; const g = at(0, 1, pages[1][k]); return { x: g.X, y: g.Y, r: g.r, rot: 0 }; };
      if (gaps > 0.01) {
        ctx.setLineDash([4, 5]);
        for (let k = HAS; k < BASE; k += 1) { const g = spot(k); line(ring(g.x, g.y, g.r * 0.86), css.line, gaps * (hotRisk >= 0 ? 0.45 : 1), 1.3); }
        ctx.setLineDash([]);
      }

      /* page 3: the trunk and branches stop at each hexagon's edge; the workflows line runs right */
      const wt = sstep(1.1, 1.7, P) * (1 - sstep(2.02, 2.22, P)) * shown;
      if (wt > 0.01) {
        const sl = s.slots[2], T = pages[2], px = (x) => sl.cx + x * sl.S, py = (y) => sl.cy - y * sl.S, edge = T[0].r * 0.9, end = T[18].y, trunk = TRUNK * treeZ;
        const hotA = sstep(1.85, 2, P) * (1 - sstep(2, 2.15, P)), rowHot = hotA > 0.01 ? s.treeHot : -1, ink = (row) => (row === rowHot ? css.rim : css.line), inkA = (row) => wt * (row === rowHot ? 1 : rowHot >= 0 ? 0.3 : 0.7), inkW = (row) => (row === rowHot ? 2.2 : 1.4);
        line([[px(trunk), py(T[0].y)], [px(trunk), py(lerp(T[0].y, end, sstep(1.1, 1.7, P)))]], css.line, wt * (rowHot >= 0 ? 0.3 : 0.7), 1.4);
        FILES.forEach(([, row], k) => {
          const first = !k || FILES[k - 1][1] !== row, h = T[k], a0 = first ? trunk : T[k - 1].x + edge, b0 = h.x - edge, w = P >= 2 ? 1 : i === 1 ? now[k].e : 0;
          if (w > 0.02) line([[px(a0), py(h.y)], [px(lerp(a0, b0, w)), py(h.y)]], ink(row), inkA(row), inkW(row));
        });
        const p = T[FLOW], grow = sstep(1.7, 1.96, P), far = T[N - 1].x + 0.06 * treeZ;
        if (grow > 0.01) {
          line([[px(p.x + edge), py(p.y)], [px(lerp(p.x + edge, far, grow)), py(p.y)]], ink(2), inkA(2), inkW(2));
          for (let n = 0; n < 7; n += 1) {
            const b = T[BASE + n], w = sstep(0.55, 1, P >= 2 ? 1 : budOf(n, f)), to = b.y - Math.sign(b.y - p.y) * edge;
            if (w > 0.01) line([[px(b.x), py(p.y)], [px(b.x), py(lerp(p.y, to, w))]], ink(2), inkA(2), inkW(2));
          }
        }
        /* the hovered row joins up with its line of text */
        if (rowHot >= 0 && s.rowAt) {
          const ks = T.filter((h) => h.row === rowHot), ex = rowHot === 2 ? far : Math.max(...ks.map((h) => h.x)) + edge, y0 = py(ks[0].row === 2 ? p.y : ks[0].y), bend = px(far) + 28;
          line([[px(ex), y0], [bend, y0], [s.rowAt.x - 10, s.rowAt.y]], css.rim, hotA, 1.6);
        }
      }

      /* page 4: the links between the hexagons draw in, and follow them */
      const w3 = sstep(2.55, 3, P) * (1 - sstep(3.02, 3.4, P)) * shown, hotCheck = Math.abs(P - 3) < 0.3 ? s.hot : -1;
      if (w3 > 0.01) LINKS.forEach(([a, b, c0], n) => {
        const A = now[a], B = now[b], mine = hotCheck === (c0 >= 0 ? c0 : a - BASE), lit = hotCheck >= 0 ? mine : c0 >= 0 && s.checks > c0 + 0.9;
        const d = Math.hypot(B.x - A.x, B.y - A.y) || 1, ux = (B.x - A.x) / d, uy = (B.y - A.y) / d;
        const from = [A.x + ux * A.r * 0.9, A.y + uy * A.r * 0.9], to = [B.x - ux * B.r * 0.9, B.y - uy * B.r * 0.9];
        line(part([from, to], sstep(n * 0.02, 0.6 + n * 0.02, w3)), lit ? css.rim : css.line, w3 * (lit ? 1 : hotCheck >= 0 ? 0.2 : 0.5), lit ? 2.2 : 1.3);
      });

      /* page 5: the four paths draw in behind the milestones */
      const w4 = sstep(3.55, 3.98, P) * (1 - sstep(4.02, 4.4, P)) * shown;
      if (w4 > 0.01) {
        const sl = s.slots[4];
        LX.forEach((x, n) => {
          const pts = []; for (let q = 0; q <= 44; q += 1) { const y = -1.02 + (q / 44) * 2.04; pts.push([sl.cx + x * open(y) * sl.S, sl.cy - y * sl.S]); }
          const on = s.lane === n;
          line(part(pts, w4), on ? css.rim : css.line, w4 * (on ? 1 : s.laneHot >= 0 ? 0.25 : 0.6), on ? 2.4 : 1.5);
        });
      }

      /* page 6: one package around the packed hexagons */
      const w5 = sstep(4.5, 4.88, P) * (1 - sstep(5.05, 5.4, P)) * shown;
      if (w5 > 0.01) { const sl = s.slots[5]; line(part(ring(sl.cx, sl.cy, sl.S * 0.82, PI / 6), w5), css.rim, w5, 2.2); line(part(ring(sl.cx, sl.cy, sl.S * 0.92, PI / 6), w5), css.line, w5 * 0.45, 1.2); }

      /* the hexagons; a hovered row or plan lifts its own and quietens the rest */
      const hotTree = sstep(1.85, 2, P) * (1 - sstep(2, 2.15, P)) > 0.5 ? s.treeHot : -1, hotPlan = Math.abs(P - 4) < 0.15 ? s.laneHot : -1;
      const dimFor = (k) => (hotPlan >= 0 ? k !== 0 && k !== END && !LANE_K[hotPlan].includes(k) : hotCheck >= 0 && k > 0 && (k < BASE ? rimOwner(k) : k) !== BASE + hotCheck);
      const draw = (img, size, h, a) => {
        if (a < 0.01 || !img) return;
        ctx.save(); ctx.translate(h.x, h.y); ctx.rotate(h.rot); const k = h.r / size; ctx.scale(k, k);
        ctx.globalAlpha = a; ctx.drawImage(img, -img.width / 2, -img.height / 2); ctx.restore();
      };
      now.forEach((h, k) => {
        if (h.r < 0.3) return;
        /* page 5: the paths stop at each hexagon's edge instead of running through it */
        if (w4 > 0.01 && k < BASE) { ctx.beginPath(); ring(h.x, h.y, h.r).forEach((p, n) => ctx[n ? 'lineTo' : 'moveTo'](p[0], p[1])); ctx.globalAlpha = w4; ctx.fillStyle = css.bg; ctx.fill(); ctx.globalAlpha = 1; }
        if (dimFor(k)) h.a *= 0.35;
        if (k >= BASE) { draw(art[CHECKS[k - BASE]], SPR, h, h.a); return; }
        /* a file's own design shows from its arrival in the tree; on page 4 only the centre keeps it */
        const own = (k < HAS ? sstep(0.4, 0.9, P) : i < 1 ? 0 : i === 1 ? sstep(0.72, 1, h.e) : 1) * (k ? 1 - sstep(2.15, 2.8, P) : 1 - sstep(3.1, 3.6, P));
        if (own > 0.01) { draw(art[FILES[k][0]], SPR, h, h.a * own); draw(k === 0 ? centreSpr : S[k % 3], SPR, h, h.a * (1 - own)); return; }
        if (k < 2 && grow > 0.01) { draw(rimSpr, BIG, h, h.a * grow); draw(S[k === 0 ? 3 : (k % 3)], SPR, h, h.a * (1 - grow)); return; }
        const img = k === 0 ? centreSpr : S[k % 3];
        draw(img, SPR, h, h.a * (k < 7 ? 1 : 0.85 + 0.15 * sstep(0, 1, P)));
      });
      for (let c0 = 0; c0 < 7; c0 += 1) {
        const h = now[BASE + c0], w = sstep(2.7, 3, P) * (1 - sstep(3, 3.3, P)), hot = hotCheck === c0, lit = hotCheck >= 0 ? hot : s.checks > c0 + 0.9;
        if (w > 0.01 && lit) { ctx.shadowColor = css.rim; ctx.shadowBlur = 12 * dpr; line(ring(h.x, h.y, h.r * 1.14), css.rim, w, hot ? 3 : 2); ctx.shadowBlur = 0; ctx.shadowColor = 'transparent'; }
      }
      /* page 2: the four files join up with their row; the gaps stay empty */
      if (hotRisk >= 0 && gaps > 0.01) {
        let far = null;
        for (let k = 0; k < HAS; k += 1) {
          const g = spot(k); if (!far || g.x > far.x) far = g;
          ctx.shadowColor = css.rim; ctx.shadowBlur = 10 * dpr; line(ring(g.x, g.y, g.r * 1.14), css.rim, gaps, 1.8); ctx.shadowBlur = 0; ctx.shadowColor = 'transparent';
        }
        if (far && s.rowAt) { const sl = s.slots[1], bend = sl.cx + sl.S * 1.22; line([[far.x + far.r * 1.0, far.y], [Math.max(bend, far.x + far.r), far.y], [s.rowAt.x - 10, s.rowAt.y]], css.rim, gaps, 1.6); }
      }
      if (hotTree >= 0) now.forEach((h, k) => { if (pages[2][k].row === hotTree) { ctx.shadowColor = css.rim; ctx.shadowBlur = 10 * dpr; line(ring(h.x, h.y, h.r * 1.14), css.rim, 1, 1.8); ctx.shadowBlur = 0; ctx.shadowColor = 'transparent'; } });
      if (hotPlan >= 0) LANE_K[hotPlan].forEach((k) => { const h = now[k]; ctx.shadowColor = css.rim; ctx.shadowBlur = 10 * dpr; line(ring(h.x, h.y, h.r * 1.14), css.rim, 1, 1.8); ctx.shadowBlur = 0; ctx.shadowColor = 'transparent'; });
      /* on a phone Start needs more room than one cell, so its hexagon opens over its neighbours */
      if (s.stacked && P < 0.3) {
        const h = now[0], a = (1 - P / 0.3) * shown, r = h.r * 1.3;
        ctx.beginPath(); ring(h.x, h.y, r).forEach((p, n) => ctx[n ? 'lineTo' : 'moveTo'](p[0], p[1])); ctx.globalAlpha = a; ctx.fillStyle = css.bg; ctx.fill(); ctx.globalAlpha = 1;
        draw(centreSpr, SPR, { ...h, r }, a);
      }
      /* hovering Start lifts its own hexagon, with a glow */
      if (s.hubLift > 0.01) {
        const h = now[0], r = h.r * (s.stacked ? 1.3 : 1) * (1 + 0.07 * s.hubLift);
        ctx.beginPath(); ring(h.x, h.y, r, h.rot).forEach((p, n) => ctx[n ? 'lineTo' : 'moveTo'](p[0], p[1])); ctx.globalAlpha = s.hubLift * h.a; ctx.fillStyle = css.bg; ctx.fill(); ctx.globalAlpha = 1;
        draw(centreSpr, SPR, { ...h, r }, h.a);
        ctx.shadowColor = css.rim; ctx.shadowBlur = 10 * dpr; line(ring(h.x, h.y, r, h.rot), css.rim, h.a * s.hubLift, 1.8); ctx.shadowBlur = 0; ctx.shadowColor = 'transparent';
      }
      if (s.pulse > 0) { ctx.beginPath(); ctx.arc(s.px, s.py, s.pulse * s.S * 2, 0, TAU); ctx.globalAlpha = (1 - s.pulse) * 0.6; ctx.strokeStyle = css.rim; ctx.lineWidth = 2; ctx.stroke(); ctx.globalAlpha = 1; }
    }
    resize();
    return {
      resize, render,
      /* a palette's sprites are made once, and the symbols a few a frame, so the switch never stalls */
      setPalette(p, ready) {
        const rgb = (c) => `rgb(${c.map((v) => Math.round(v * 255)).join(',')})`;
        css = { rim: rgb(p.rim), line: rgb(p.line), bg: getComputedStyle(document.documentElement).getPropertyValue('--bg').trim() };
        if (!made.has(p)) made.set(p, { base: [0, 1, 2, 3].map((k) => sprite(p, k, SPR)), rim: sprite(p, 4, BIG), art: {} });
        const set = made.get(p), names = [...FILES.map((f) => f[0]), ...CHECKS], mine = ++job;
        S = set.base; centreSpr = S[3]; rimSpr = set.rim;
        names.forEach((name) => { if (set.art[name]) art[name] = set.art[name]; });
        const todo = names.filter((name) => !set.art[name]);
        const step = () => {
          if (mine !== job) return;
          todo.splice(0, 3).forEach((name) => { art[name] = set.art[name] = sprite(p, 5, SPR, name); });
          if (todo.length) requestAnimationFrame(step); else if (ready) ready();
        };
        step();
      },
      setDuo(_, g) { pages[last()] = withHidden(lastPage(g.centres), { x: 0, y: 0 }); },
      setTree(z) { treeZ = z; pages[2] = tree(z); },
      /* what the mouse is over: a gap, a row of the tree, a check, or a plan's path */
      riskRowAt(x, y, sl) {
        const k = pages[1].findIndex((h, n) => n < HAS && Math.hypot(sl.cx + h.x * sl.S - x, sl.cy - h.y * sl.S - y) < h.r * sl.S * 0.87);
        return k < 0 ? -1 : 0;
      },
      treeRowAt(x, y, sl) {
        const T = pages[2], px = (v) => sl.cx + v * sl.S, py = (v) => sl.cy - v * sl.S, hit = T.find((h) => Math.hypot(px(h.x) - x, py(h.y) - y) < h.r * sl.S * 1.1);
        if (hit) return hit.row;
        const flowY = py(T[FLOW].y), line = T.find((h, k) => (k < BASE
          ? Math.abs(py(h.y) - y) < 8 && x > px(TRUNK * treeZ) && x < px(h.row === 2 ? T[N - 1].x : h.x)
          : Math.abs(px(h.x) - x) < 8 && y > Math.min(flowY, py(h.y)) && y < Math.max(flowY, py(h.y))));
        return line ? line.row : -1;
      },
      checkAt(x, y, sl) {
        const P3 = pages[3], px = (v) => sl.cx + v * sl.S, py = (v) => sl.cy - v * sl.S, on = (h) => Math.hypot(px(h.x) - x, py(h.y) - y) < h.r * sl.S * 1.15;
        for (let n = 0; n < 7; n += 1) if (on(P3[BASE + n])) return n;
        for (let k = 1; k < BASE; k += 1) if (on(P3[k])) return rimOwner(k) - BASE;
        for (let n = 0; n < 7; n += 1) {
          const bx = px(P3[BASE + n].x) - sl.cx, by = py(P3[BASE + n].y) - sl.cy, t = c01(((x - sl.cx) * bx + (y - sl.cy) * by) / (bx * bx + by * by));
          if (Math.hypot(sl.cx + bx * t - x, sl.cy + by * t - y) < 8 && !on(P3[0])) return n;
        }
        return -1;
      },
      laneAt(x, y, sl) {
        const v = (sl.cy - y) / sl.S; if (Math.abs(v) > 1.05) return -1;
        let best = -1, gap = 20;
        LX.forEach((lx, n) => { const d = Math.abs(sl.cx + lx * open(v) * sl.S - x); if (d < gap) { gap = d; best = n; } });
        return best;
      },
    };
    function last() { return pages.length - 1; }
  }
