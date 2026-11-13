(() => {
  const RATE_OPTIONS = [
    { value: 'auto', label: '自动' },
    { value: '60', label: '60 Hz' },
    { value: '90', label: '90 Hz' },
    { value: '120', label: '120 Hz' },
    { value: '144', label: '144 Hz' },
  ];
  const VALUE_TO_LABEL = Object.fromEntries(RATE_OPTIONS.map(option => [option.value, option.label]));
  const API_PATH = '/data/adb/modules/plf110_display_oc/webroot/api.sh';

  const state = {
    apps: [],
    policies: new Map(),
    policyData: PlfPolicies.parse(''),
    backupAvailable: false,
    filter: 'all',
    query: '',
    activeApp: null,
    selectedRate: null,
    toastTimer: null,
    sheetCloseTimer: null,
    reloading: false,
    appRows: [],
    rowsDirty: true,
    emptyState: null,
    filterGesture: null,
    refreshSpinning: false,
    restoreCloseTimer: null,
    overlayNavigation: null,
  };

  const elements = {
    appList: document.getElementById('app-list'),
    appCount: document.getElementById('app-count'),
    configuredCount: document.getElementById('configured-count'),
    connectionStatus: document.getElementById('connection-status'),
    statusLight: document.getElementById('status-light'),
    search: document.getElementById('search-input'),
    filterTabsContainer: document.querySelector('.filter-tabs'),
    filterTabs: [...document.querySelectorAll('.filter-tab')],
    refreshButton: document.getElementById('refresh-button'),
    restoreButton: document.getElementById('restore-button'),
    sheetBackdrop: document.getElementById('sheet-backdrop'),
    sheetIcon: document.getElementById('sheet-icon'),
    sheetTitle: document.getElementById('sheet-title'),
    sheetPackage: document.getElementById('sheet-package'),
    sheetPolicyHint: document.getElementById('sheet-policy-hint'),
    rateOptions: document.getElementById('rate-options'),
    saveButton: document.getElementById('save-button'),
    toast: document.getElementById('toast'),
    restoreDialog: document.getElementById('restore-dialog'),
  };

  const fallbackIcon = '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="5" y="3.8" width="14" height="16.4" rx="3.2" stroke="currentColor" stroke-width="1.6"/><path d="M9 7.5h6M9 11h6m-6 3.5h3" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>';

  function shellQuote(value) {
    return `'${String(value).replace(/'/g, "'\\''")}'`;
  }

  function execRoot(command) {
    return new Promise((resolve, reject) => {
      if (!window.ksu || typeof window.ksu.exec !== 'function') {
        reject(new Error('未检测到 KernelSU WebUI 接口'));
        return;
      }
      const callbackName = `plf110_exec_${Date.now()}_${Math.random().toString(36).slice(2)}`;
      window[callbackName] = (errno, stdout, stderr) => {
        delete window[callbackName];
        if (Number(errno) !== 0) {
          reject(new Error((stderr || stdout || `root 命令退出码 ${errno}`).trim()));
          return;
        }
        resolve(stdout || '');
      };
      try {
        window.ksu.exec(command, '{}', callbackName);
      } catch (error) {
        delete window[callbackName];
        reject(error);
      }
    });
  }

  function runApi(...args) {
    const command = ['sh', shellQuote(`${API_PATH}`), ...args.map(shellQuote)].join(' ');
    return execRoot(command);
  }

  function setConnection(text, status) {
    elements.connectionStatus.textContent = text;
    elements.statusLight.classList.toggle('is-ready', status === 'ready');
    elements.statusLight.classList.toggle('is-error', status === 'error');
  }

  function parseConfig(output, apps) {
    state.policyData = PlfPolicies.parse(output, apps.map(app => app.packageName));
    state.policies = state.policyData.overrides;
    state.backupAvailable = state.policyData.backupAvailable;
    elements.restoreButton.hidden = !state.backupAvailable;
    return state.policyData.managed;
  }

  function parsePackageList(raw) {
    const value = JSON.parse(raw);
    if (!Array.isArray(value)) throw new Error('应用列表格式不正确');
    return value.map(item => typeof item === 'string' ? item : item.packageName).filter(Boolean);
  }

  function loadPackages() {
    if (!window.ksu || typeof window.ksu.listPackages !== 'function' || typeof window.ksu.getPackagesInfo !== 'function') {
      throw new Error('当前管理器不支持读取应用信息，请更新 KernelSU Manager');
    }
    const names = parsePackageList(window.ksu.listPackages('user'));
    const infos = JSON.parse(window.ksu.getPackagesInfo(JSON.stringify(names)));
    const byName = new Map();
    if (Array.isArray(infos)) {
      for (const info of infos) {
        if (!info?.packageName || info.error) continue;
        const previous = byName.get(info.packageName);
        if (!previous || Number(info.userId || 0) === 0) byName.set(info.packageName, info);
      }
    }
    return names.map(packageName => {
      const info = byName.get(packageName) || {};
      return {
        packageName,
        label: info.appLabel || packageName,
        versionName: info.versionName || '',
      };
    }).sort((a, b) => a.label.localeCompare(b.label, 'zh-CN', { sensitivity: 'base' }));
  }

  function activeRate(packageName) {
    return PlfPolicies.describe(state.policyData, packageName).rate;
  }

  function rateLabel(rate) {
    if (rate.startsWith('custom:')) return `模式 ${rate.slice(7)}`;
    return VALUE_TO_LABEL[rate] || '自动';
  }

  function iconNode(packageName, className) {
    const wrapper = document.createElement('span');
    wrapper.className = className;
    wrapper.innerHTML = fallbackIcon;
    const image = document.createElement('img');
    image.alt = '';
    image.loading = 'lazy';
    image.decoding = 'async';
    image.addEventListener('load', () => { wrapper.classList.add('has-image'); }, { once: true });
    image.addEventListener('error', () => { image.remove(); }, { once: true });
    wrapper.append(image);
    image.src = `ksu://icon/${encodeURIComponent(packageName)}`;
    return wrapper;
  }

  function makeRow(app) {
    const row = document.createElement('button');
    row.className = 'app-row';
    row.type = 'button';
    const policy = PlfPolicies.describe(state.policyData, app.packageName);
    row.setAttribute('aria-label', `${app.label}，${app.packageName}，${policy.label}，${policy.sceneLabel}`);
    row.append(iconNode(app.packageName, 'app-icon'));

    const copy = document.createElement('span');
    copy.className = 'app-copy';
    const name = document.createElement('span');
    name.className = 'app-name';
    name.textContent = app.label;
    const packageName = document.createElement('span');
    packageName.className = 'app-package';
    packageName.textContent = app.packageName;
    copy.append(name, packageName);
    if (policy.sceneLabel) {
      const hint = document.createElement('span');
      hint.className = 'app-policy';
      hint.textContent = policy.sceneLabel;
      copy.append(hint);
    }

    const rate = activeRate(app.packageName);
    const tag = document.createElement('span');
    const rateClass = rate === 'auto' ? 'is-system' : rate.startsWith('custom:') ? 'is-unknown' : `is-rate-${rate}`;
    tag.className = `rate-tag ${rateClass}`;
    const tagLabel = document.createElement('span');
    tagLabel.className = 'rate-tag-label';
    tagLabel.textContent = policy.label;
    tag.append(tagLabel);

    const chevron = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    chevron.setAttribute('viewBox', '0 0 24 24');
    chevron.setAttribute('fill', 'none');
    chevron.setAttribute('class', 'row-chevron');
    chevron.innerHTML = '<path d="m9 5 7 7-7 7" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>';
    row.append(copy, tag, chevron);
    row.addEventListener('click', () => openSheet(app));
    return row;
  }

  function renderApps() {
    const query = state.query.trim().toLocaleLowerCase('zh-CN');
    const rebuild = state.rowsDirty;
    if (rebuild) {
      state.appRows = state.apps.map(app => ({
        app, node: makeRow(app),
        searchKey: `${app.label.toLocaleLowerCase('zh-CN')}\n${app.packageName.toLowerCase()}`,
      }));
      const empty = document.createElement('div');
      empty.className = 'list-placeholder is-empty';
      const title = document.createElement('strong');
      title.textContent = state.apps.length === 0 ? '没有可显示的应用' : '没有匹配的应用';
      const detail = document.createElement('span');
      detail.textContent = state.apps.length === 0 ? '应用列表为空或当前账号不可见' : '试试其他关键词';
      empty.append(title, detail);
      state.emptyState = empty;
      elements.appCount.textContent = String(state.apps.length);
      elements.configuredCount.textContent = String(state.apps.filter(app => state.policies.has(app.packageName)).length);
    }
    // Reuse rows and loaded icons. Filter/typing does not rebuild the entire DOM.
    const fragment = rebuild ? document.createDocumentFragment() : null;
    let visible = 0;
    for (const entry of state.appRows) {
      const show = (state.filter !== 'configured' || state.policies.has(entry.app.packageName)) &&
        (!query || entry.searchKey.includes(query));
      if (entry.node.hidden === show) entry.node.hidden = !show;
      entry.node.classList.toggle('is-first-visible', show && visible === 0);
      if (show) visible++;
      if (fragment) fragment.append(entry.node);
    }
    state.emptyState.hidden = visible !== 0;
    if (fragment) {
      fragment.append(state.emptyState);
      elements.appList.replaceChildren(fragment);
      state.rowsDirty = false;
    }
    elements.appList.setAttribute('aria-busy', 'false');
  }

  async function reload(showToast = false) {
    if (state.reloading) return;
    state.reloading = true;
    elements.appList.setAttribute('aria-busy', 'true');
    setConnection('正在读取配置', 'loading');
    try {
      const apps = loadPackages();
      const config = await runApi('list', ...apps.map(app => app.packageName));
      parseConfig(config, apps);
      state.apps = apps;
      state.rowsDirty = true;
      state.filterGesture?.cancel();
      renderApps();
      setConnection(state.policyData.backend === 'vendor' ? '配置已同步' : '配置已同步 · 默认值为文件参考', 'ready');
      if (showToast) showToastMessage('应用列表已更新');
    } catch (error) {
      state.rowsDirty = true;
      elements.appList.setAttribute('aria-busy', 'false');
      elements.appList.innerHTML = '';
      const placeholder = document.createElement('div');
      placeholder.className = 'list-placeholder is-empty';
      const title = document.createElement('strong');
      title.textContent = '无法读取应用刷新率';
      const detail = document.createElement('span');
      detail.textContent = error.message || '请确认模块已启用';
      placeholder.append(title, detail);
      elements.appList.append(placeholder);
      elements.appCount.textContent = '--';
      elements.configuredCount.textContent = '--';
      setConnection('连接失败', 'error');
      if (showToast) showToastMessage(error.message || '读取失败');
    } finally {
      state.reloading = false;
    }
  }

  function renderRateOptions() {
    elements.rateOptions.replaceChildren();
    for (const option of RATE_OPTIONS) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'rate-option';
      button.setAttribute('role', 'radio');
      button.setAttribute('aria-checked', state.selectedRate === option.value ? 'true' : 'false');
      const label = document.createElement('span');
      label.className = 'rate-option-label';
      const policy = state.activeApp ? PlfPolicies.describe(state.policyData, state.activeApp.packageName) : null;
      label.textContent = option.value === 'auto' && policy ? `自动（${policy.defaultLabel}）` : option.label;
      const indicator = document.createElement('span');
      indicator.className = 'radio-indicator';
      indicator.setAttribute('aria-hidden', 'true');
      button.append(label, indicator);
      button.addEventListener('click', () => {
        state.selectedRate = option.value;
        renderRateOptions();
        elements.saveButton.disabled = false;
      });
      elements.rateOptions.append(button);
    }
  }

  function openSheet(app) {
    state.overlayNavigation?.cancelGesture();
    window.clearTimeout(state.sheetCloseTimer);
    state.sheetCloseTimer = null;
    elements.sheetBackdrop.classList.remove('is-closing');
    state.activeApp = app;
    const policy = PlfPolicies.describe(state.policyData, app.packageName);
    state.selectedRate = policy.selection;
    elements.sheetIcon.replaceWith(iconNode(app.packageName, 'sheet-icon'));
    elements.sheetIcon = document.querySelector('.sheet-icon');
    elements.sheetTitle.textContent = app.label;
    elements.sheetPackage.textContent = app.packageName;
    elements.sheetPolicyHint.textContent = [policy.defaultLabel, policy.sceneLabel, '此处为配置，不代表实时帧率'].filter(Boolean).join('；');
    elements.saveButton.disabled = true;
    renderRateOptions();
    elements.sheetBackdrop.hidden = false;
    state.overlayNavigation?.enter('sheet');
    document.body.style.overflow = 'hidden';
    document.getElementById('sheet-close').focus();
  }

  function closeSheet() {
    if (elements.sheetBackdrop.hidden || elements.sheetBackdrop.classList.contains('is-closing')) return;
    state.overlayNavigation?.prepareClose('sheet');
    const finishClose = () => {
      state.sheetCloseTimer = null;
      elements.sheetBackdrop.hidden = true;
      elements.sheetBackdrop.classList.remove('is-closing');
      document.body.style.overflow = '';
      state.activeApp = null;
      state.overlayNavigation?.finish('sheet');
      elements.refreshButton.focus();
    };
    elements.sheetBackdrop.classList.add('is-closing');
    state.sheetCloseTimer = window.setTimeout(finishClose, 200);
  }

  function openRestoreDialog() {
    if (elements.restoreDialog.open) return;
    window.clearTimeout(state.restoreCloseTimer);
    state.restoreCloseTimer = null;
    state.overlayNavigation?.cancelGesture();
    elements.restoreDialog.classList.remove('is-closing');
    elements.restoreDialog.showModal();
    state.overlayNavigation?.enter('restore');
  }

  function closeRestoreDialog() {
    if (!elements.restoreDialog.open || elements.restoreDialog.classList.contains('is-closing')) return;
    state.overlayNavigation?.prepareClose('restore');
    elements.restoreDialog.classList.add('is-closing');
    state.restoreCloseTimer = window.setTimeout(() => {
      state.restoreCloseTimer = null;
      elements.restoreDialog.close();
      elements.restoreDialog.classList.remove('is-closing');
      state.overlayNavigation?.finish('restore');
      elements.restoreButton.focus();
    }, 200);
  }

  function currentOverlay() {
    if (elements.restoreDialog.open && !elements.restoreDialog.classList.contains('is-closing')) {
      return { key: 'restore', layer: elements.restoreDialog, panel: elements.restoreDialog };
    }
    if (!elements.sheetBackdrop.hidden && !elements.sheetBackdrop.classList.contains('is-closing')) {
      return { key: 'sheet', layer: elements.sheetBackdrop, panel: document.querySelector('.rate-sheet') };
    }
    return null;
  }

  async function saveRate() {
    if (!state.activeApp || !state.selectedRate) return;
    const app = state.activeApp;
    const savedRate = state.selectedRate;
    elements.saveButton.disabled = true;
    elements.saveButton.innerHTML = '<span class="spinner"></span> 正在保存';
    try {
      await runApi('set', app.packageName, savedRate);
      closeSheet();
      await reload();
      showToastMessage(`${app.label} · ${rateLabel(savedRate)} 已保存`);
    } catch (error) {
      showToastMessage(error.message || '保存失败');
    } finally {
      elements.saveButton.innerHTML = '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m5 12.5 4.2 4.2L19 7" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>保存';
      elements.saveButton.disabled = false;
    }
  }

  function showToastMessage(message) {
    window.clearTimeout(state.toastTimer);
    elements.toast.textContent = message;
    elements.toast.classList.add('is-visible');
    state.toastTimer = window.setTimeout(() => elements.toast.classList.remove('is-visible'), 2600);
  }

  function setFilter(filter) {
    if (!['all', 'configured'].includes(filter) || state.filter === filter) return;
    state.filter = filter;
    for (const tab of elements.filterTabs) {
      const selected = tab.dataset.filter === filter;
      tab.classList.toggle('is-active', selected);
      tab.setAttribute('aria-selected', selected ? 'true' : 'false');
    }
    elements.filterTabsContainer.dataset.activeFilter = filter;
    renderApps();
  }

  function bindEvents() {
    const finishRefreshSpin = () => {
      state.refreshSpinning = false;
      elements.refreshButton.classList.remove('is-spinning');
    };
    elements.refreshButton.addEventListener('animationend', event => {
      if (event.animationName === 'refresh-spin') finishRefreshSpin();
    });
    elements.refreshButton.addEventListener('animationcancel', event => {
      if (event.animationName === 'refresh-spin') finishRefreshSpin();
    });
    elements.refreshButton.addEventListener('click', event => {
      if (state.reloading || state.refreshSpinning) return;
      state.refreshSpinning = true;
      elements.refreshButton.classList.add('is-spinning');
      // Finish at the animation's 360deg endpoint; further taps cannot restart it.
      // Do not time out a circle midway if the WebView/bridge stalls a frame.
      if (event.detail > 0) elements.refreshButton.blur();
      reload(true);
    });
    elements.search.addEventListener('input', () => {
      state.query = elements.search.value;
      renderApps();
    });
    elements.filterTabs.forEach(tab => tab.addEventListener('click', () => setFilter(tab.dataset.filter)));
    if (window.PlfFilterGesture) {
      state.filterGesture = window.PlfFilterGesture.attach({
        container: elements.filterTabsContainer,
        tabs: elements.filterTabs,
        getValue: () => state.filter,
        onCommit: setFilter,
      });
    }
    elements.saveButton.addEventListener('click', saveRate);
    document.getElementById('sheet-close').addEventListener('click', closeSheet);
    document.getElementById('cancel-button').addEventListener('click', closeSheet);
    elements.sheetBackdrop.addEventListener('click', event => {
      if (event.target === elements.sheetBackdrop) closeSheet();
    });
    document.getElementById('restore-cancel').addEventListener('click', closeRestoreDialog);
    elements.restoreButton.addEventListener('click', openRestoreDialog);
    elements.restoreDialog.addEventListener('cancel', event => { event.preventDefault(); closeRestoreDialog(); });
    document.getElementById('restore-confirm').addEventListener('click', async () => {
      const button = document.getElementById('restore-confirm');
      button.disabled = true;
      try {
        await runApi('restore');
        closeRestoreDialog();
        await reload();
        showToastMessage('已恢复首次修改前的配置');
      } catch (error) {
        showToastMessage(error.message || '恢复失败');
      } finally {
        button.disabled = false;
      }
    });
    document.addEventListener('keydown', event => {
      if (event.key === '/' && !event.metaKey && !event.ctrlKey && document.activeElement !== elements.search && !elements.sheetBackdrop.hidden) return;
      if (event.key === '/' && !event.metaKey && !event.ctrlKey && document.activeElement !== elements.search && elements.sheetBackdrop.hidden) {
        event.preventDefault();
        elements.search.focus();
      }
      if (event.key === 'Escape' && currentOverlay()) {
        event.preventDefault();
        if (currentOverlay().key === 'restore') closeRestoreDialog();
        else closeSheet();
      }
    });
  }

  if (window.PlfOverlayNavigation) {
    state.overlayNavigation = window.PlfOverlayNavigation.attach({
      getOverlay: currentOverlay,
      onBack: key => { if (key === 'restore') closeRestoreDialog(); else if (key === 'sheet') closeSheet(); },
    });
  }
  bindEvents();
  reload();
})();
