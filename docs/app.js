(() => {
  const stage = document.getElementById("stage");
  const strip = document.getElementById("strip");
  const status = document.getElementById("status");
  const openButton = document.getElementById("open");
  if (!stage || !strip) return;

  const GAP = 14;
  const MAX_WINDOWS = 12;
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

  const apps = ["Notes", "Browser", "Terminal", "Mail", "Design", "Music", "Maps", "Calendar", "Photos", "Chat", "Files", "Reader"];
  const lines = (...widths) => widths.map((w) => `<div class="ln" style="width:${w}%"></div>`).join("");
  const bodies = {
    Notes: () => `<div class="body">${lines(40, 92, 86, 94, 60, 90, 74)}</div>`,
    Browser: () => `<div class="body"><div class="ln head"></div>${lines(96, 88)}<div class="thumbs"><i></i><i></i><i></i></div>${lines(80, 92)}</div>`,
    Terminal: () => `<div class="body term"><div><b>~</b> swift build</div><div>Compiling StripCore</div><div>Build complete</div><div><b>~</b> swift run StripCheck</div><div>all checks passed</div><div><b>~</b> ▍</div></div>`,
    Mail: () => `<div class="body">${lines(34, 90, 70, 38, 94, 62, 40, 88)}</div>`,
    Photos: () => `<div class="body"><div class="thumbs"><i></i><i></i><i></i><i></i><i></i><i></i></div></div>`,
    Design: () => `<div class="body"><div class="thumbs"><i></i><i></i></div>${lines(60, 90, 76)}</div>`,
  };
  const body = (name) => (bodies[name] || (() => `<div class="body">${lines(38, 92, 78, 90, 56, 84)}</div>`))();

  const wins = [];
  let focus = 1;
  let offset = 0;
  let nextApp = 0;
  let interacted = false;

  const makeWindow = (name, animate) => {
    const el = document.createElement("article");
    el.className = "win" + (animate && !reduceMotion ? " enter" : "");
    el.dataset.app = name;
    el.innerHTML = `<header class="bar"><i></i><i></i><i></i><span>${name}</span></header>${body(name)}`;
    return el;
  };

  const metrics = () => {
    const width = wins[0] ? wins[0].offsetWidth : 0;
    const view = stage.clientWidth - 28;
    const total = wins.length * width + Math.max(0, wins.length - 1) * GAP;
    return { width, view, step: width + GAP, max: Math.max(0, total - view) };
  };

  const clamp = (value) => Math.min(Math.max(0, value), metrics().max);

  const apply = (animate) => {
    strip.style.transition = animate && !reduceMotion ? "transform 320ms cubic-bezier(0.2, 0.8, 0.2, 1)" : "none";
    strip.style.transform = `translate3d(${-offset}px, 0, 0)`;
  };

  const reveal = (index, animate = true) => {
    const m = metrics();
    const left = index * m.step;
    const right = left + m.width;
    if (left < offset) offset = left;
    else if (right > offset + m.view) offset = right - m.view;
    offset = clamp(offset);
    apply(animate);
  };

  const describe = () => {
    status.textContent = `${wins[focus].dataset.app}, window ${focus + 1} of ${wins.length}`;
    openButton.disabled = wins.length >= MAX_WINDOWS;
  };

  const setFocus = (index, scroll = true) => {
    focus = Math.min(Math.max(0, index), wins.length - 1);
    wins.forEach((el, i) => el.setAttribute("aria-current", i === focus ? "true" : "false"));
    if (scroll) reveal(focus);
    describe();
  };

  const snap = (animate = true) => {
    const m = metrics();
    offset = clamp(Math.round(offset / m.step) * m.step);
    apply(animate);
  };

  const openWindow = (animate = true) => {
    if (wins.length >= MAX_WINDOWS) return;
    const el = makeWindow(apps[nextApp % apps.length], animate);
    nextApp += 1;
    const at = wins.length ? focus + 1 : 0;
    strip.insertBefore(el, wins[at] || null);
    wins.splice(at, 0, el);
    setFocus(at);
  };

  apps.slice(0, 4).forEach((name) => {
    const el = makeWindow(name, false);
    strip.appendChild(el);
    wins.push(el);
  });
  nextApp = 4;
  setFocus(1, false);
  apply(false);

  openButton.addEventListener("click", () => {
    interacted = true;
    openWindow();
  });

  strip.addEventListener("click", (event) => {
    if (dragMoved) return;
    const target = event.target.closest(".win");
    if (target) {
      interacted = true;
      setFocus(wins.indexOf(target));
    }
  });

  let drag = null;
  let dragMoved = false;

  stage.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    interacted = true;
    dragMoved = false;
    drag = { x: event.clientX, start: offset, lastX: event.clientX, lastT: performance.now(), velocity: 0 };
    stage.setPointerCapture(event.pointerId);
  });

  stage.addEventListener("pointermove", (event) => {
    if (!drag) return;
    const dx = event.clientX - drag.x;
    if (Math.abs(dx) > 4) dragMoved = true;
    offset = clamp(drag.start - dx);
    apply(false);
    const now = performance.now();
    const dt = Math.max(1, now - drag.lastT);
    drag.velocity = 0.6 * drag.velocity + 0.4 * ((event.clientX - drag.lastX) / dt);
    drag.lastX = event.clientX;
    drag.lastT = now;
  });

  const endDrag = () => {
    if (!drag) return;
    if (dragMoved) {
      offset = clamp(offset - drag.velocity * 220);
      snap(true);
      setTimeout(() => { dragMoved = false; }, 0);
    }
    drag = null;
  };
  stage.addEventListener("pointerup", endDrag);
  stage.addEventListener("pointercancel", endDrag);

  let wheelTimer = 0;
  stage.addEventListener("wheel", (event) => {
    const sideways = Math.abs(event.deltaX) > Math.abs(event.deltaY);
    if (!sideways && !event.shiftKey) return;
    event.preventDefault();
    interacted = true;
    offset = clamp(offset + (sideways ? event.deltaX : event.deltaY));
    apply(false);
    clearTimeout(wheelTimer);
    wheelTimer = setTimeout(() => snap(true), 140);
  }, { passive: false });

  stage.addEventListener("keydown", (event) => {
    const moves = { ArrowLeft: -1, ArrowRight: 1 };
    if (event.key in moves) {
      event.preventDefault();
      interacted = true;
      setFocus(focus + moves[event.key]);
    } else if (event.key === "Home" || event.key === "End") {
      event.preventDefault();
      interacted = true;
      setFocus(event.key === "Home" ? 0 : wins.length - 1);
    }
  });

  addEventListener("resize", () => {
    offset = clamp(offset);
    apply(false);
  });

  if (!reduceMotion) {
    setTimeout(() => {
      if (!interacted) openWindow();
    }, 1400);
  }
})();
