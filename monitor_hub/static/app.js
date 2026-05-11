'use strict';

// ── State ──────────────────────────────────────────────────────────────────
let sources = [];
let settings = {};
let editingId = null;        // null = add mode, string = edit mode
let identifySession = null;  // { session_id, source_id, poll_timer }

// ── API helpers ────────────────────────────────────────────────────────────
async function api(method, path, body) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (body !== undefined) opts.body = JSON.stringify(body);
  const res = await fetch(path, opts);
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { error: text }; }
  if (!res.ok) throw Object.assign(new Error(data.error || res.statusText), { data });
  return data;
}

const GET    = (p)    => api('GET',    p);
const POST   = (p, b) => api('POST',   p, b);
const PUT    = (p, b) => api('PUT',    p, b);
const DELETE = (p)    => api('DELETE', p);

function showToast(message, type = 'info') {
  const stack = document.getElementById('toast-stack');
  if (!stack) return;
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  stack.appendChild(toast);
  setTimeout(() => { toast.classList.add('toast-hide'); }, 2600);
  setTimeout(() => { toast.remove(); }, 3100);
}

function showConfirmPanel(message, onConfirm) {
  const panel = document.getElementById('confirm-panel');
  if (!panel) return;
  panel.hidden = false;
  panel.innerHTML = `
    <div class="confirm-message">${message}</div>
    <div class="confirm-actions">
      <button class="btn btn-danger" data-action="confirm">Delete</button>
      <button class="btn btn-secondary" data-action="cancel">Cancel</button>
    </div>`;

  panel.querySelector('[data-action="confirm"]').addEventListener('click', async () => {
    panel.hidden = true;
    await onConfirm();
  });
  panel.querySelector('[data-action="cancel"]').addEventListener('click', () => {
    panel.hidden = true;
  });
}

// ── Render ─────────────────────────────────────────────────────────────────
function vcpLabel(source) {
  const confirmed = source.vcp_code_confirmed ? ' ✓' : '';
  if (source.vcp_codes && Object.keys(source.vcp_codes).length) {
    const parts = Object.entries(source.vcp_codes)
      .sort(([a], [b]) => Number(a) - Number(b))
      .map(([mon, vcp]) => `${mon}→${vcp}`)
      .join(', ');
    return `<span class="vcp-ok">VCP: ${parts}${confirmed}</span>`;
  }
  if (source.vcp_code == null) return `<span class="vcp-missing">VCP: not set ⚠</span>`;
  return `<span class="vcp-ok">VCP: ${source.vcp_code}${confirmed}</span>`;
}

function renderSources() {
  const grid = document.getElementById('sources-grid');
  const empty = document.getElementById('empty-msg');
  grid.innerHTML = '';

  if (sources.length === 0) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;

  for (const src of sources) {
    const card = document.createElement('div');
    card.className = 'card';
    card.dataset.id = src.id;
    card.innerHTML = `
      <div class="card-name" title="${src.name}">${src.name}</div>
      <div class="card-vcp">${vcpLabel(src)}</div>
      <div class="card-actions">
        <button class="btn btn-secondary btn-identify">Identify</button>
        <button class="btn btn-secondary btn-edit">Edit</button>
        <button class="btn btn-danger btn-delete">✕</button>
      </div>`;

    card.querySelector('.btn-identify').addEventListener('click', () => startIdentify(src));
    card.querySelector('.btn-edit').addEventListener('click', () => openEditModal(src));
    card.querySelector('.btn-delete').addEventListener('click', () => deleteSource(src));
    renderSwitchButtons(card, src);
    grid.appendChild(card);
  }
}

function hasVcp(src) {
  return src.vcp_code != null ||
    (src.vcp_codes && Object.keys(src.vcp_codes).length > 0);
}

function renderSwitchButtons(card, src) {
  if (!hasVcp(src)) return;
  const row = document.createElement('div');
  row.className = 'card-switch';
  const btn = document.createElement('button');
  btn.className = 'btn btn-switch';
  btn.textContent = '→ Apply';
  btn.title = `Switch local monitors to ${src.name}`;
  btn.addEventListener('click', () => doSwitch(src, btn));
  row.appendChild(btn);
  card.appendChild(row);
}

async function doSwitch(src, trigger) {
  trigger.disabled = true;
  const orig = trigger.textContent;
  trigger.textContent = '↻';
  try {
    await POST(`/api/sources/${src.id}/switch`, {});
    trigger.textContent = '✓';
    trigger.classList.add('btn-switch-ok');
    setTimeout(() => {
      trigger.textContent = orig;
      trigger.classList.remove('btn-switch-ok');
      trigger.disabled = false;
    }, 2000);
  } catch (e) {
    trigger.textContent = '✕';
    trigger.classList.add('btn-switch-err');
    trigger.title = e.message;
    setTimeout(() => {
      trigger.textContent = orig;
      trigger.classList.remove('btn-switch-err');
      trigger.disabled = false;
    }, 2000);
  }
}

// ── Data loading ───────────────────────────────────────────────────────────
async function loadAll() {
  [sources, settings] = await Promise.all([
    GET('/api/sources').then(d => d.sources),
    GET('/api/settings'),
  ]);
  const localControlsVisible = !!settings.local_request;
  document.getElementById('btn-enable-tray').hidden =
    !localControlsVisible || !!settings.tray_active;
  document.getElementById('btn-quit').hidden = !localControlsVisible;
  renderSources();
}

// Refresh just sources every 15s for status updates
setInterval(async () => {
  try {
    const d = await GET('/api/sources');
    sources = d.sources;
    renderSources();
  } catch {}
}, 15000);

// ── Add / Edit Modal ───────────────────────────────────────────────────────
function openAddModal() {
  editingId = null;
  document.getElementById('modal-source-title').textContent = 'Add Source';
  document.getElementById('src-name').value = '';
  document.getElementById('src-vcp-manual').value = '';
  showModal('modal-source');
}

function openEditModal(src) {
  editingId = src.id;
  document.getElementById('modal-source-title').textContent = 'Edit Source';
  document.getElementById('src-name').value = src.name;
  if (src.vcp_codes && Object.keys(src.vcp_codes).length) {
    const val = Object.entries(src.vcp_codes)
      .sort(([a], [b]) => Number(a) - Number(b))
      .map(([, v]) => v)
      .join(', ');
    document.getElementById('src-vcp-manual').value = val;
  } else if (src.vcp_code != null) {
    document.getElementById('src-vcp-manual').value = src.vcp_code;
  } else {
    document.getElementById('src-vcp-manual').value = '';
  }
  showModal('modal-source');
}

async function saveSource() {
  const name = document.getElementById('src-name').value.trim();
  const vcpRaw = document.getElementById('src-vcp-manual').value.trim();

  if (!name) {
    showToast('Name is required.', 'error');
    return;
  }

  let vcp_codes = null;
  let vcp_code = null;
  if (vcpRaw) {
    const vals = vcpRaw.split(',').map(s => parseInt(s.trim())).filter(n => !isNaN(n));
    if (vals.length === 1) {
      vcp_code = vals[0];
    } else if (vals.length > 1) {
      vcp_codes = {};
      vals.forEach((v, i) => { vcp_codes[String(i)] = v; });
    }
  }

  try {
    const payload = { name };
    if (vcp_codes) { payload.vcp_codes = vcp_codes; payload.vcp_code_confirmed = true; }
    else if (vcp_code != null) { payload.vcp_code = vcp_code; payload.vcp_code_confirmed = true; }

    if (editingId) {
      await PUT(`/api/sources/${editingId}`, payload);
    } else {
      await POST('/api/sources', payload);
    }
    closeModal('modal-source');
    await loadAll();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function deleteSource(src) {
  showConfirmPanel(`Delete "${src.name}"?`, async () => {
    try {
      await DELETE(`/api/sources/${src.id}`);
      await loadAll();
      showToast(`Deleted ${src.name}`, 'success');
    } catch (e) {
      showToast(e.message, 'error');
    }
  });
}

// ── Settings Modal ─────────────────────────────────────────────────────────
function openSettingsModal() {
  document.getElementById('set-dwell').value = settings.identify_dwell_ms ?? 2000;
  document.getElementById('set-candidates').value =
    (settings.identify_candidates || []).join(',');
  showModal('modal-settings');
}

async function saveSettings() {
  const dwell = parseInt(document.getElementById('set-dwell').value) || 2000;
  const candidatesRaw = document.getElementById('set-candidates').value;
  const candidates = candidatesRaw.split(',').map(s => parseInt(s.trim())).filter(n => !isNaN(n));

  try {
    settings = await PUT('/api/settings', {
      identify_dwell_ms: dwell,
      identify_candidates: candidates,
    });
    closeModal('modal-settings');
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function enableTray() {
  const btn = document.getElementById('btn-enable-tray');
  btn.disabled = true;
  btn.textContent = 'Switching…';
  try {
    await POST('/api/system/enable-tray', {});
    showToast('Switching to tray — reconnecting…', 'info');
    setTimeout(() => location.reload(), 3000);
  } catch (e) {
    btn.disabled = false;
    btn.textContent = '⬛ Enable Tray';
    showToast(e.message, 'error');
  }
}

async function quitServer() {
  try {
    await POST('/api/system/quit', {});
    showToast('Server stopped.', 'info');
  } catch (_) {
    showToast('Server stopped.', 'info');
  }
}

// ── Identify ───────────────────────────────────────────────────────────────
// identifySession: { session_id, source_id, probed: {monitor_id: vcp_code} }

async function startIdentify(src) {
  document.getElementById('id-source-name').textContent = src.name;
  document.getElementById('id-monitors').innerHTML = '<p class="hint">Connecting to agent…</p>';
  document.getElementById('id-probe-decision').hidden = true;
  document.getElementById('id-confirm').disabled = true;
  showModal('modal-identify');

  try {
    const data = await POST(`/api/identify/${src.id}/start`);
    identifySession = { session_id: data.session_id, source_id: src.id, probed: {} };
    renderMonitorRows(data.monitors, data.candidates, data.prior_vcps || {},
                      data.saved_vcp_codes || {}, data.saved_vcp_code);
  } catch (e) {
    document.getElementById('id-monitors').innerHTML = '';
    showToast(e.message, 'error');
  }
}

function renderMonitorRows(monitors, candidates, priorVcps = {}, savedVcps = {}, savedVcp = null) {
  const container = document.getElementById('id-monitors');
  container.innerHTML = '';

  for (const mon of monitors) {
    const section = document.createElement('div');
    section.className = 'identify-monitor';
    section.dataset.monitorId = mon.id;

    const header = document.createElement('div');
    header.className = 'identify-monitor-header';
    const currentVcp = priorVcps[mon.id];
    const savedForMonitor = savedVcps[mon.id] ?? savedVcps[String(mon.id)] ?? savedVcp;
    const currentLabel = currentVcp == null ? 'current VCP: unreadable' : `current VCP: ${currentVcp}`;
    const savedLabel = savedForMonitor == null ? '' : `saved VCP: ${savedForMonitor}`;
    header.innerHTML = `<span class="monitor-label">Monitor ${mon.id}</span>
      <span class="monitor-desc">${mon.description || ''}</span>
      <span class="monitor-current">${currentLabel}</span>
      <span class="monitor-saved">${savedLabel}</span>
      <span class="monitor-probed" id="probed-${mon.id}"></span>`;

    const btnRow = document.createElement('div');
    btnRow.className = 'identify-candidates';

    for (const vcp of candidates) {
      const btn = document.createElement('button');
      btn.className = 'btn btn-secondary btn-vcp-probe';
      if (savedForMonitor != null && Number(savedForMonitor) === Number(vcp)) {
        btn.classList.add('btn-active');
      }
      btn.textContent = `VCP ${vcp}`;
      btn.dataset.vcp = vcp;
      btn.dataset.monitorId = mon.id;
      btn.addEventListener('click', () => probeVcp(mon.id, vcp));
      btnRow.appendChild(btn);
    }

    section.appendChild(header);
    section.appendChild(btnRow);
    container.appendChild(section);
  }
}

async function probeVcp(monitorId, vcp) {
  if (!identifySession) return;

  const allBtns = document.querySelectorAll('.btn-vcp-probe');
  allBtns.forEach(b => { b.disabled = true; });

  const activeBtn = document.querySelector(
    `.btn-vcp-probe[data-monitor-id="${monitorId}"][data-vcp="${vcp}"]`
  );
  if (activeBtn) activeBtn.textContent = `VCP ${vcp} ↻`;

  try {
    const result = await POST(`/api/identify/${identifySession.session_id}/probe`,
                              { monitor_id: monitorId, vcp_code: vcp });

    showProbeDecision(monitorId, vcp, result, activeBtn);
  } catch (e) {
    showToast(e.message, 'error');
  } finally {
    allBtns.forEach(b => { b.disabled = false; });
    if (activeBtn) activeBtn.textContent = `VCP ${vcp}`;
  }
}

function showProbeDecision(monitorId, vcp, result, activeBtn) {
  const box = document.getElementById('id-probe-decision');
  const seconds = Math.round((result.dwell_ms || 3000) / 1000);
  const restoreNote = result.restored_vcp_code != null
    ? `for ${seconds}s, then restored to VCP ${result.restored_vcp_code}`
    : `(monitor switched — auto-restore not available on this platform)`;
  box.hidden = false;
  box.innerHTML = `
    <div>
      <strong>Monitor ${monitorId}</strong> tested VCP ${vcp} ${restoreNote}.
    </div>
    <div class="probe-actions">
      <button class="btn btn-success" data-action="save">Save VCP ${vcp}</button>
      <button class="btn btn-secondary" data-action="discard">Discard</button>
    </div>`;

  box.querySelector('[data-action="save"]').addEventListener('click', () => {
    const probedEl = document.getElementById(`probed-${monitorId}`);
    identifySession.probed[monitorId] = vcp;
    if (probedEl) probedEl.textContent = `→ VCP ${vcp}`;
    document.querySelectorAll(`.btn-vcp-probe[data-monitor-id="${monitorId}"]`)
      .forEach(b => b.classList.remove('btn-active'));
    if (activeBtn) activeBtn.classList.add('btn-active');
    document.getElementById('id-confirm').disabled = false;
    box.hidden = true;
    showToast(`Monitor ${monitorId}: VCP ${vcp} saved for confirm`, 'success');
  });

  box.querySelector('[data-action="discard"]').addEventListener('click', () => {
    const probedEl = document.getElementById(`probed-${monitorId}`);
    if (probedEl) probedEl.textContent = `tested VCP ${vcp}, not saved`;
    document.getElementById('id-confirm').disabled =
      Object.keys(identifySession.probed).length === 0;
    box.hidden = true;
    showToast(`Monitor ${monitorId}: VCP ${vcp} discarded`);
  });
}

async function confirmIdentify() {
  if (!identifySession || !Object.keys(identifySession.probed).length) return;
  try {
    await POST(`/api/identify/${identifySession.session_id}/confirm`,
               { vcp_codes: identifySession.probed });
  } catch (e) {
    showToast(e.message, 'error');
    return;
  }
  closeModal('modal-identify');
  await loadAll();
  showToast('VCP codes confirmed', 'success');
}

async function cancelIdentify() {
  if (identifySession) {
    try { await POST(`/api/identify/${identifySession.session_id}/cancel`); } catch {}
    identifySession = null;
  }
  closeModal('modal-identify');
}

// ── Modal helpers ──────────────────────────────────────────────────────────
function showModal(id) {
  document.getElementById('overlay').hidden = false;
  document.getElementById(id).hidden = false;
}

function closeModal(id) {
  document.getElementById(id).hidden = true;
  const anyOpen = ['modal-source', 'modal-identify', 'modal-settings']
    .some(m => !document.getElementById(m).hidden);
  if (!anyOpen) document.getElementById('overlay').hidden = true;
  if (id === 'modal-identify') identifySession = null;
}

// ── Wire up events ─────────────────────────────────────────────────────────
document.getElementById('btn-add').addEventListener('click', openAddModal);
document.getElementById('btn-enable-tray').addEventListener('click', enableTray);
document.getElementById('btn-quit').addEventListener('click', quitServer);
document.getElementById('btn-settings').addEventListener('click', openSettingsModal);
document.getElementById('src-cancel').addEventListener('click', () => closeModal('modal-source'));
document.getElementById('src-save').addEventListener('click', saveSource);
document.getElementById('set-cancel').addEventListener('click', () => closeModal('modal-settings'));
document.getElementById('set-save').addEventListener('click', saveSettings);
document.getElementById('id-confirm').addEventListener('click', confirmIdentify);
document.getElementById('id-cancel').addEventListener('click', cancelIdentify);
document.getElementById('overlay').addEventListener('click', () => {
  ['modal-source', 'modal-settings'].forEach(m => {
    if (!document.getElementById(m).hidden) closeModal(m);
  });
});

// ── Init ───────────────────────────────────────────────────────────────────
loadAll();
