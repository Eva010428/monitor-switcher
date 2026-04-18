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

function statusDot(status) {
  const cls = { online: 'dot-online', offline: 'dot-offline' }[status] || 'dot-unknown';
  return `<span class="dot ${cls}"></span>${status ?? 'unknown'}`;
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
      <div class="card-ip">${src.ip}:${src.agent_port ?? 5001}</div>
      <div class="card-vcp">${vcpLabel(src)}</div>
      <div class="card-status">${statusDot(src.status)}</div>
      <div class="card-actions">
        <button class="btn btn-secondary btn-identify">Identify</button>
        <button class="btn btn-secondary btn-edit">Edit</button>
        <button class="btn btn-danger btn-delete">✕</button>
      </div>`;

    card.querySelector('.btn-identify').addEventListener('click', () => startIdentify(src));
    card.querySelector('.btn-edit').addEventListener('click', () => openEditModal(src));
    card.querySelector('.btn-delete').addEventListener('click', () => deleteSource(src));
    grid.appendChild(card);
  }
}

// ── Data loading ───────────────────────────────────────────────────────────
async function loadAll() {
  [sources, settings] = await Promise.all([
    GET('/api/sources').then(d => d.sources),
    GET('/api/settings'),
  ]);
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
  document.getElementById('src-ip').value = '';
  document.getElementById('src-agent-port').value = '5001';
  document.getElementById('src-vcp').value = '';
  showModal('modal-source');
}

function openEditModal(src) {
  editingId = src.id;
  document.getElementById('modal-source-title').textContent = 'Edit Source';
  document.getElementById('src-name').value = src.name;
  document.getElementById('src-ip').value = src.ip;
  document.getElementById('src-agent-port').value = src.agent_port ?? 5001;
  document.getElementById('src-vcp').value = src.vcp_code ?? '';
  showModal('modal-source');
}

async function saveSource() {
  const name = document.getElementById('src-name').value.trim();
  const ip = document.getElementById('src-ip').value.trim();
  const agentPort = parseInt(document.getElementById('src-agent-port').value) || 5001;
  const vcpRaw = document.getElementById('src-vcp').value.trim();
  const vcp_code = vcpRaw === '' ? null : parseInt(vcpRaw);

  if (!name || !ip) { alert('Name and IP are required.'); return; }

  try {
    if (editingId) {
      await PUT(`/api/sources/${editingId}`, { name, ip, agent_port: agentPort, vcp_code });
    } else {
      await POST('/api/sources', { name, ip, agent_port: agentPort, vcp_code });
    }
    closeModal('modal-source');
    await loadAll();
  } catch (e) {
    alert(e.message);
  }
}

async function deleteSource(src) {
  if (!confirm(`Delete "${src.name}"?`)) return;
  try {
    await DELETE(`/api/sources/${src.id}`);
    await loadAll();
  } catch (e) {
    alert(e.message);
  }
}

// ── Settings Modal ─────────────────────────────────────────────────────────
function openSettingsModal() {
  document.getElementById('set-ask').checked = settings.ask_on_multiple ?? true;
  document.getElementById('set-dwell').value = settings.identify_dwell_ms ?? 2000;
  document.getElementById('set-candidates').value =
    (settings.identify_candidates || []).join(',');

  const sel = document.getElementById('set-default-target');
  sel.innerHTML = '<option value="">— none —</option>';
  for (const src of sources) {
    const opt = document.createElement('option');
    opt.value = src.id;
    opt.textContent = src.name;
    if (src.id === settings.default_target_id) opt.selected = true;
    sel.appendChild(opt);
  }
  showModal('modal-settings');
}

async function saveSettings() {
  const ask = document.getElementById('set-ask').checked;
  const dwell = parseInt(document.getElementById('set-dwell').value) || 2000;
  const candidatesRaw = document.getElementById('set-candidates').value;
  const candidates = candidatesRaw.split(',').map(s => parseInt(s.trim())).filter(n => !isNaN(n));
  const defaultId = document.getElementById('set-default-target').value || null;

  try {
    settings = await PUT('/api/settings', {
      ask_on_multiple: ask,
      identify_dwell_ms: dwell,
      identify_candidates: candidates,
      default_target_id: defaultId,
    });
    closeModal('modal-settings');
  } catch (e) {
    alert(e.message);
  }
}

// ── Identify ───────────────────────────────────────────────────────────────
// identifySession: { session_id, source_id, probed: {monitor_id: vcp_code} }

async function startIdentify(src) {
  document.getElementById('id-source-name').textContent = src.name;
  document.getElementById('id-monitors').innerHTML = '<p class="hint">Connecting to agent…</p>';
  document.getElementById('id-error').hidden = true;
  document.getElementById('id-confirm').disabled = true;
  showModal('modal-identify');

  try {
    const data = await POST(`/api/identify/${src.id}/start`);
    identifySession = { session_id: data.session_id, source_id: src.id, probed: {} };
    renderMonitorRows(data.monitors, data.candidates);
  } catch (e) {
    document.getElementById('id-monitors').innerHTML = '';
    document.getElementById('id-error').textContent = e.message;
    document.getElementById('id-error').hidden = false;
  }
}

function renderMonitorRows(monitors, candidates) {
  const container = document.getElementById('id-monitors');
  container.innerHTML = '';

  for (const mon of monitors) {
    const section = document.createElement('div');
    section.className = 'identify-monitor';
    section.dataset.monitorId = mon.id;

    const header = document.createElement('div');
    header.className = 'identify-monitor-header';
    header.innerHTML = `<span class="monitor-label">Monitor ${mon.id}</span>
      <span class="monitor-desc">${mon.description || ''}</span>
      <span class="monitor-probed" id="probed-${mon.id}"></span>`;

    const btnRow = document.createElement('div');
    btnRow.className = 'identify-candidates';

    for (const vcp of candidates) {
      const btn = document.createElement('button');
      btn.className = 'btn btn-secondary btn-vcp-probe';
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

  document.getElementById('id-error').hidden = true;

  try {
    await POST(`/api/identify/${identifySession.session_id}/probe`,
               { monitor_id: monitorId, vcp_code: vcp });

    identifySession.probed[monitorId] = vcp;

    // Update the "last probed" badge on this monitor's row
    const probedEl = document.getElementById(`probed-${monitorId}`);
    if (probedEl) probedEl.textContent = `→ VCP ${vcp}`;

    // Highlight active button per monitor (clear siblings first)
    document.querySelectorAll(`.btn-vcp-probe[data-monitor-id="${monitorId}"]`)
      .forEach(b => b.classList.remove('btn-active'));
    if (activeBtn) activeBtn.classList.add('btn-active');

    // Enable confirm once at least one monitor is probed
    document.getElementById('id-confirm').disabled = false;
  } catch (e) {
    document.getElementById('id-error').textContent = e.message;
    document.getElementById('id-error').hidden = false;
  } finally {
    allBtns.forEach(b => { b.disabled = false; });
    if (activeBtn) activeBtn.textContent = `VCP ${vcp}`;
  }
}

async function confirmIdentify() {
  if (!identifySession || !Object.keys(identifySession.probed).length) return;
  try {
    await POST(`/api/identify/${identifySession.session_id}/confirm`,
               { vcp_codes: identifySession.probed });
  } catch (e) {
    document.getElementById('id-error').textContent = e.message;
    document.getElementById('id-error').hidden = false;
    return;
  }
  closeModal('modal-identify');
  await loadAll();
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
