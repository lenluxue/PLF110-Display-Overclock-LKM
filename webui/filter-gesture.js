/* Local UI gesture only. No root calls, setting writes, or background animation loop. */
((root, factory) => {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.PlfFilterGesture = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  function attach({ container, tabs, getValue, onCommit, win = window }) {
    if (typeof win.PointerEvent !== 'function') return { cancel() {}, dispose() {} };
    const HOLD_MS = 220, SLOP = 8;
    let gesture = null, frame = null, ignoreClickUntil = 0;
    const clamp = (value, max) => Math.max(0, Math.min(max, value));
    function measure() {
      const box = container.getBoundingClientRect();
      const boxes = tabs.map(tab => tab.getBoundingClientRect());
      if (!(boxes[0].width > 0 && boxes[1].width > 0)) return boxes;
      const values = {
        '--filter-origin-x': boxes[0].left - box.left - (container.clientLeft || 0),
        '--filter-all-width': boxes[0].width,
        '--filter-configured-width': boxes[1].width,
        '--filter-travel-x': boxes[1].left - boxes[0].left,
        '--filter-origin-y': boxes[0].top - box.top - (container.clientTop || 0),
        '--filter-thumb-height': boxes[0].height,
      };
      for (const [key, value] of Object.entries(values)) {
        if (!Number.isFinite(value)) continue;
        const next = `${value}px`;
        if (container.style.getPropertyValue(key) !== next) container.style.setProperty(key, next);
      }
      return boxes;
    }

    function paint() {
      frame = null;
      if (gesture) container.style.setProperty('--filter-drag-x', `${gesture.offset}px`);
    }
    function queuePaint() {
      if (frame === null) frame = win.requestAnimationFrame(paint);
    }
    function cancel() {
      const previous = gesture;
      gesture = null;
      if (previous?.active) ignoreClickUntil = Date.now() + 700;
      if (previous) win.clearTimeout(previous.timer);
      if (frame !== null) win.cancelAnimationFrame(frame);
      frame = null;
      container.classList.remove('is-dragging');
      container.style.removeProperty('--filter-drag-x');
      if (previous && container.hasPointerCapture(previous.id)) {
        try { container.releasePointerCapture(previous.id); } catch (_) {}
      }
    }
    function down(event) {
      if (gesture || event.isPrimary === false || event.button !== 0) return;
      ignoreClickUntil = 0;
      const boxes = measure();
      const centers = boxes.map(box => box.left + box.width / 2);
      const travel = centers[1] - centers[0];
      if (!(travel > 0)) return;
      const startOffset = getValue() === tabs[1].dataset.filter ? travel : 0;
      const current = {
        id: event.pointerId, x: event.clientX, y: event.clientY,
        firstCenter: centers[0], travel, active: false,
        offset: startOffset, startOffset, dragged: false, timer: null,
      };
      gesture = current;
      // Short taps must not touch the thumb: native click performs one transition.
      // This prevents down-preview -> up-reset -> click-move tugging/reversals.
      current.timer = win.setTimeout(() => {
        if (gesture !== current) return;
        try { container.setPointerCapture(current.id); }
        catch (_) { cancel(); return; }
        current.active = true;
        // Activate at the selected position; holding either tab cannot jump the thumb.
        paint();
        container.classList.add('is-dragging');
      }, HOLD_MS);
    }
    function move(event) {
      const current = gesture;
      if (!current || event.pointerId !== current.id) return;
      if (!current.active) {
        if (Math.hypot(event.clientX - current.x, event.clientY - current.y) > SLOP) cancel();
        return;
      }
      if (Math.abs(event.clientX - current.x) > 3) current.dragged = true;
      current.offset = clamp(current.startOffset + event.clientX - current.x, current.travel);
      if (event.cancelable) event.preventDefault();
      queuePaint();
    }
    function up(event) {
      const current = gesture;
      if (!current || event.pointerId !== current.id) return;
      if (current.active) {
        // A held, stationary press still selects its tab; a drag is anchored to
        // the original thumb so activation, tracking and snap-back never teleport.
        current.offset = current.dragged || Math.abs(event.clientX - current.x) > 3
          ? clamp(current.startOffset + event.clientX - current.x, current.travel)
          : clamp(current.x - current.firstCenter, current.travel);
        const value = tabs[current.offset >= current.travel / 2 ? 1 : 0].dataset.filter;
        ignoreClickUntil = Date.now() + 700;
        if (event.cancelable) event.preventDefault();
        try { if (value !== getValue()) onCommit(value); }
        finally { cancel(); }
      } else cancel(); // Leave ordinary click/keyboard behavior untouched.
    }
    function interrupted(event) {
      if (!gesture || event.pointerId !== gesture.id) return;
      if (gesture.active) ignoreClickUntil = Date.now() + 700;
      cancel();
    }
    function click(event) {
      // A new pointerdown clears this guard; subsequent intentional taps are not blocked.
      if (event.detail !== 0 && Date.now() < ignoreClickUntil) {
        ignoreClickUntil = 0;
        event.preventDefault();
        event.stopPropagation();
      }
    }
    function contextMenu(event) { event.preventDefault(); }
    function blurred() { cancel(); }
    function resized() { cancel(); measure(); }
    measure();
    const observer = typeof win.ResizeObserver === 'function' ? new win.ResizeObserver(resized) : null;
    if (observer) { observer.observe(container); tabs.forEach(tab => observer.observe(tab)); }
    container.addEventListener('pointerdown', down);
    container.addEventListener('pointermove', move, { passive: false });
    container.addEventListener('pointerup', up, { passive: false });
    container.addEventListener('pointercancel', interrupted);
    container.addEventListener('lostpointercapture', interrupted);
    container.addEventListener('click', click, true);
    container.addEventListener('contextmenu', contextMenu);
    win.addEventListener('blur', blurred);
    win.addEventListener('resize', resized);
    return {
      cancel,
      dispose() {
        cancel();
        observer?.disconnect();
        container.removeEventListener('pointerdown', down);
        container.removeEventListener('pointermove', move);
        container.removeEventListener('pointerup', up);
        container.removeEventListener('pointercancel', interrupted);
        container.removeEventListener('lostpointercapture', interrupted);
        container.removeEventListener('click', click, true);
        container.removeEventListener('contextmenu', contextMenu);
        win.removeEventListener('blur', blurred);
        win.removeEventListener('resize', resized);
      },
    };
  }
  return { attach };
});
