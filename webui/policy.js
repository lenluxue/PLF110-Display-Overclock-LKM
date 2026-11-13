/* SPDX-License-Identifier: GPL-2.0-only */
((root, factory) => {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.PlfPolicies = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  const IDS = { 0: 'auto', 1: '90', 2: '60', 3: '120', 4: '144' };
  const packagePattern = /^[A-Za-z0-9_][A-Za-z0-9_.]*$/;
  const idValue = id => /^\d+$/.test(id) ? (IDS[id] || `custom:${id}`) : null;
  const rateLabel = rate => rate === 'auto' ? '自动' : rate?.startsWith('custom:') ? `模式 ${rate.slice(7)}` : `${rate} Hz`;

  function parse(output, packageNames = []) {
    const overrides = new Map(), managed = new Map(), defaults = new Map();
    const base = new Map(), scenes = new Map(), follow = new Set();
    const systemOverrides = new Map(), vendorDefaults = new Map();
    let backupAvailable = false, backend = 'file', mode = 3, globalBase = null;
    for (const line of output.split(/\r?\n/)) {
      const [kind, name, value] = line.split('\t');
      if (kind === 'INFO') {
        if (name === 'backup=1') backupAvailable = true;
        else if (name === 'policy_backend=vendor') backend = 'vendor';
        else if (name === 'policy_mode=8') mode = 8;
        else if (name === 'policy_mode=3') mode = 3;
        continue;
      }
      if (kind === 'BASE_GLOBAL' && value) { globalBase = value; continue; }
      if (!name || !packagePattern.test(name) || !value) continue;
      const rate = idValue(value);
      if (kind === 'XML' && rate) overrides.set(name, rate);
      else if (kind === 'SYSTEM_OVERRIDE' && rate) systemOverrides.set(name, rate);
      else if ((kind === 'DEFAULT' || kind === 'DEFAULT_FALLBACK') && rate) vendorDefaults.set(name, rate);
      else if (kind === 'MANAGED' && /^(auto|60|90|120|144)$/.test(value)) managed.set(name, value);
      else if (kind === 'BASE' && /^\d+(?:-\d+)+$/.test(value)) base.set(name, value);
      else if (kind === 'ACTIVITY' && /^\d+(?:-\d+)+$/.test(value)) {
        if (!scenes.has(name)) scenes.set(name, new Set());
        scenes.get(name).add(value);
      } else if (kind === 'FOLLOW_APP') follow.add(name);
    }
    const atMode = vector => {
      if (!vector) return null;
      const ids = vector.split('-'), position = mode > 3 ? 4 : 3;
      return ids.length > position ? idValue(ids[position]) : null;
    };
    const names = new Set([...packageNames, ...base.keys(), ...vendorDefaults.keys(), ...follow]);
    for (const name of names) {
      if (follow.has(name)) defaults.set(name, { rate: 'auto', source: 'app' });
      else if (vendorDefaults.has(name)) defaults.set(name, { rate: vendorDefaults.get(name), source: 'vendor' });
      else {
        const rate = atMode(base.get(name) || globalBase);
        if (rate) defaults.set(name, { rate, source: 'file' });
      }
    }
    for (const [name, rate] of systemOverrides) overrides.set(name, rate);
    for (const [name, rate] of overrides) if (rate === 'auto') overrides.delete(name);
    for (const [name, rate] of managed) {
      if (rate === 'auto') overrides.delete(name);
      else overrides.set(name, rate);
    }
    const sceneRates = new Map();
    for (const [name, vectors] of scenes) {
      const rates = [...new Set([...vectors].map(atMode).filter(rate => rate && rate !== 'auto'))];
      if (rates.length) sceneRates.set(name, rates);
    }
    return { overrides, defaults, sceneRates, managed, backupAvailable, backend, mode };
  }

  function describe(data, name) {
    const manual = data.overrides.has(name);
    const entry = data.defaults.get(name) || { rate: 'auto', source: 'unknown' };
    const rate = manual ? data.overrides.get(name) : entry.rate;
    const origin = manual ? 'manual' : entry.source;
    const label = manual ? `手动 ${rateLabel(rate)}` : origin === 'app' ? '跟随应用'
      : rate === 'auto' ? '系统默认' : origin === 'file' ? `文件 ${rateLabel(rate)}` : `默认 ${rateLabel(rate)}`;
    const differingScenes = (data.sceneRates.get(name) || []).filter(value => value !== rate);
    const sceneLabel = differingScenes.length ? `部分页面规则：${differingScenes.map(rateLabel).join(' / ')}` : '';
    const defaultLabel = entry.source === 'app' ? '跟随应用' : entry.rate === 'auto' ? '系统默认'
      : `${entry.source === 'file' ? '文件参考' : '系统默认'} ${rateLabel(entry.rate)}`;
    return { rate, origin, label, sceneLabel, defaultLabel, manual, selection: manual ? rate : 'auto' };
  }
  return { parse, describe, rateLabel };
});
