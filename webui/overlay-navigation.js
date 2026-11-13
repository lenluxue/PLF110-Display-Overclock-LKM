/* WebUI-local overlay history + interactive edge preview. No Android/root APIs. */
((root, factory) => {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.PlfOverlayNavigation = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  function attach({ getOverlay, onBack, win = window, doc = document }) {
    const MARKER = '__plf110_overlay';
    let sequence = 0, entries = [], gesture = null, frame = null, returning = null;
    let waitingBack = false, queuedEnter = null, backTimer = null, swallowClick = false;
    const layers = new Map();
    const clamp = (n, max) => Math.max(0, Math.min(max, n));
    function clearLayer(layer) {
      layer.classList.remove('is-back-preview', 'is-back-returning');
      for (const key of ['--back-x', '--back-scale', '--back-progress', '--overlay-exit-transform']) {
        layer.style.removeProperty(key);
      }
    }
    function detachGesture() {
      const previous = gesture; gesture = null;
      if (frame !== null) win.cancelAnimationFrame(frame);
      frame = null;
      if (previous?.active && doc.documentElement.hasPointerCapture(previous.id)) {
        try { doc.documentElement.releasePointerCapture(previous.id); } catch (_) {}
      }
      return previous;
    }
    function cancelGesture() {
      const old = detachGesture();
      if (old?.active) clearLayer(old.overlay.layer);
      if (returning) {
        win.clearTimeout(returning.timer); clearLayer(returning.layer); returning = null;
      }
    }
    function enter(key) {
      const overlay = getOverlay();
      if (overlay?.key === key) { clearLayer(overlay.layer); layers.set(key, overlay.layer); }
      if (waitingBack) { queuedEnter = key; return; }
      if (entries[entries.length - 1]?.key === key) return;
      const token = `plf-${Date.now()}-${++sequence}`;
      try {
        const previous = win.history.state;
        const next = previous && typeof previous === 'object' && !Array.isArray(previous) ? { ...previous } : {};
        next[MARKER] = token;
        win.history.pushState(next, '');
        entries.push({ key, token });
      } catch (_) {
        // Sandboxed/old hosts can still use local close and edge gestures.
        entries.push({ key, token: null });
      }
    }
    function prepareClose(key) {
      const overlay = getOverlay();
      if (overlay?.key === key) {
        const value = typeof win.getComputedStyle === 'function' ? win.getComputedStyle(overlay.panel).transform : null;
        overlay.layer.style.setProperty('--overlay-exit-transform', value && value !== 'none' ? value : 'matrix(1, 0, 0, 1, 0, 0)');
        layers.set(key, overlay.layer);
      }
      const old = detachGesture();
      if (old?.active) old.overlay.layer.classList.remove('is-back-preview');
      if (returning) {
        win.clearTimeout(returning.timer); returning.layer.classList.remove('is-back-preview', 'is-back-returning'); returning = null;
      }
    }
    function finish(key) {
      const layer = layers.get(key);
      if (layer) { clearLayer(layer); layers.delete(key); }
      if (queuedEnter === key) queuedEnter = null;
      const top = entries[entries.length - 1];
      if (!top || top.key !== key) return;
      entries.pop();
      if (!top.token || win.history.state?.[MARKER] !== top.token) return;
      waitingBack = true;
      try {
        win.history.back();
        backTimer = win.setTimeout(() => {
          waitingBack = false; backTimer = null;
          const key = queuedEnter; queuedEnter = null;
          if (key && getOverlay()?.key === key) enter(key);
        }, 1000);
      } catch (_) { waitingBack = false; }
    }
    function popped(event) {
      win.clearTimeout(backTimer); backTimer = null; waitingBack = false;
      const token = event.state?.[MARKER];
      // Only consume entries owned by this WebUI; never navigate the root page.
      while (entries.length && entries[entries.length - 1].token !== token) {
        const { key } = entries.pop();
        if (getOverlay()?.key === key) onBack(key);
      }
      const key = queuedEnter; queuedEnter = null;
      if (key && getOverlay()?.key === key) enter(key);
    }
    function paint() {
      frame = null;
      if (!gesture?.active) return;
      const g = gesture, progress = clamp(g.distance / g.range, 1);
      const style = g.overlay.layer.style;
      style.setProperty('--back-x', `${g.sign * g.distance * .35}px`);
      style.setProperty('--back-scale', `${1 - progress * .065}`);
      style.setProperty('--back-progress', `${progress}`);
    }
    function down(event) {
      if (event.isPrimary !== false) swallowClick = false;
      if (gesture || returning || event.isPrimary === false || event.button !== 0) return;
      const overlay = getOverlay();
      if (!overlay) return;
      const width = win.innerWidth;
      const edge = Math.min(36, width * .1);
      const sign = event.clientX <= edge ? 1 : event.clientX >= width - edge ? -1 : 0;
      if (!sign) return;
      gesture = { id: event.pointerId, overlay, x: event.clientX, y: event.clientY,
        sign, active: false, distance: 0, range: Math.min(220, width * .6) };
    }
    function move(event) {
      const g = gesture;
      if (!g || event.pointerId !== g.id) return;
      if (getOverlay()?.key !== g.overlay.key) { cancelGesture(); return; }
      const horizontal = (event.clientX - g.x) * g.sign, vertical = Math.abs(event.clientY - g.y);
      if (!g.active) {
        if (vertical > 10 && vertical > Math.abs(horizontal)) { detachGesture(); return; }
        if (horizontal < -8) { detachGesture(); return; }
        if (horizontal < 8 || horizontal < vertical * 1.2) return;
        try { doc.documentElement.setPointerCapture(g.id); }
        catch (_) { detachGesture(); return; }
        g.active = true;
        layers.set(g.overlay.key, g.overlay.layer);
        g.overlay.layer.classList.add('is-back-preview');
      }
      g.distance = clamp(horizontal, g.range);
      if (event.cancelable) event.preventDefault();
      if (frame === null) frame = win.requestAnimationFrame(paint);
    }
    function settleCancelled(g) {
      if (!g?.active) return;
      g.overlay.layer.classList.add('is-back-returning');
      const record = { layer: g.overlay.layer, timer: null };
      returning = record;
      record.timer = win.setTimeout(() => {
        if (returning !== record) return;
        clearLayer(record.layer); returning = null;
      }, 200);
    }
    function up(event) {
      const g = gesture;
      if (!g || event.pointerId !== g.id) return;
      if (!g.active) { detachGesture(); return; }
      swallowClick = true;
      if (event.cancelable) event.preventDefault();
      const distance = clamp((event.clientX - g.x) * g.sign, g.range);
      // A deliberate quarter-range swipe commits; moving back cancels.
      if (distance >= g.range * .25) onBack(g.overlay.key);
      else settleCancelled(detachGesture());
    }
    function interrupted(event) {
      if (!gesture || event.pointerId !== gesture.id) return;
      settleCancelled(detachGesture());
    }
    function changed() { cancelGesture(); }
    function clicked(event) {
      // A cancelled edge swipe must not turn into a tap on the backdrop/button.
      if (!swallowClick || event.detail === 0) return;
      swallowClick = false;
      event.preventDefault(); event.stopPropagation();
    }
    win.addEventListener('popstate', popped);
    win.addEventListener('blur', changed);
    win.addEventListener('resize', changed);
    if (typeof win.PointerEvent === 'function') {
      doc.addEventListener('pointerdown', down, true);
      doc.addEventListener('pointermove', move, { passive: false, capture: true });
      doc.addEventListener('pointerup', up, { passive: false, capture: true });
      doc.addEventListener('pointercancel', interrupted, true);
      doc.addEventListener('click', clicked, true);
      doc.documentElement.addEventListener('lostpointercapture', interrupted);
    }
    return {
      enter, prepareClose, finish, cancelGesture,
      dispose() {
        cancelGesture(); win.clearTimeout(backTimer);
        win.removeEventListener('popstate', popped); win.removeEventListener('blur', changed); win.removeEventListener('resize', changed);
        doc.removeEventListener('pointerdown', down, true); doc.removeEventListener('pointermove', move, true);
        doc.removeEventListener('pointerup', up, true); doc.removeEventListener('pointercancel', interrupted, true);
        doc.removeEventListener('click', clicked, true);
        doc.documentElement.removeEventListener('lostpointercapture', interrupted);
      },
    };
  }
  return { attach };
});
