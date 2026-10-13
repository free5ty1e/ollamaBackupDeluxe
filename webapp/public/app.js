/* Ollama Backup Deluxe — UI logic (no dependencies) */
'use strict';
const $ = (id) => document.getElementById(id);
const humanSize = (kb) => {
  if (kb == null) return '—';
  let b = kb * 1024, u = ['B', 'KB', 'MB', 'GB', 'TB'], i = 0;
  while (b >= 1024 && i < 4) { b /= 1024; i++; }
  return `${b.toFixed(b < 10 && i > 0 ? 1 : 0)}${u[i]}`;
};

async function api(path, opts) {
  const r = await fetch(path, opts);
  const body = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(body.error || `HTTP ${r.status}`);
  return body;
}

// ---------------------------------------------------------------------------
// System panel
// ---------------------------------------------------------------------------
async function refreshSystem() {
  try {
    const s = await api('/api/system');
    const c = s.components;
    const pill = (ok, txt) => `<span class="pill ${ok ? 'ok' : 'bad'}">${txt}</span>`;
    $('system-pills').innerHTML =
      pill(c.sevenZip.present, `7-Zip ${c.sevenZip.present ? '✓' : 'missing — run prerequisites'}`) +
      pill(c.ollamaApp.present, `Ollama ${c.ollamaApp.version || (c.ollamaApp.present ? '✓' : '✗')}`) +
      pill(c.pi.present, `Pi ${c.pi.version || (c.pi.present ? '✓' : '✗')}`) +
      pill(c.claude.present, `Claude ${c.claude.version || (c.claude.present ? '✓' : '—')}`) +
      pill(c.opencode.present, `OpenCode ${c.opencode.version || (c.opencode.present ? '✓' : '—')}`) +
      pill(true, `Node ${c.node.version}`) +
      pill(!!s.modelCount, `${s.modelCount} models · ${humanSize(c.ollamaHome.sizeKb)}`);
    const item = (title, detail) => `<div class="sysitem"><b>${title}</b><span class="muted">${detail || '—'}</span></div>`;
    $('system-info').innerHTML =
      item('Ollama app', `${c.ollamaApp.version || '?'} — ${c.ollamaApp.path}`) +
      item('Ollama data', `${c.ollamaHome.path} (${humanSize(c.ollamaHome.sizeKb)})`) +
      item('Ollama app data', `${c.ollamaAppSupport.path} ${c.ollamaAppSupport.present ? '' : '(not found)'}`) +
      item('Pi', `${c.pi.version || '?'} — ${c.pi.path}`) +
      item('Claude Code', `${c.claude.version || (c.claude.present ? 'present' : 'not installed')} — ${c.claude.home}`) +
      item('OpenCode', `${c.opencode.version || (c.opencode.present ? 'present' : 'not installed')} — ${c.opencode.home}`) +
      item('Node', `${c.node.version} (${s.arch})`) +
      item('7-Zip', c.sevenZip.present ? c.sevenZip.path : 'missing — click Cancel & run scripts/prerequisites.sh') +
      item('Free disk (project volume)', humanSize(s.diskFreeKb)) +
      item('Project', s.project);
  } catch (e) { $('system-pills').innerHTML = `<span class="pill bad">API error: ${e.message}</span>`; }
}

// ---------------------------------------------------------------------------
// Job panel
// ---------------------------------------------------------------------------
let jobTimer = null, jobSeen = 0;
function showJob(title) {
  $('job-title').textContent = title;
  $('job-panel').classList.remove('hidden');
  $('job-log').textContent = '';
  jobSeen = 0;
  if (jobTimer) clearInterval(jobTimer);
  jobTimer = setInterval(pollJob, 900);
  pollJob();
}
async function pollJob() {
  try {
    const j = await api(`/api/job?since=${jobSeen}`);
    if (j.total == null) return;
    if (j.log.length) {
      jobSeen = j.total;
      const el = $('job-log');
      el.textContent += j.log.join('\n') + '\n';
      el.scrollTop = el.scrollHeight;
    }
    const st = $('job-status');
    st.textContent = j.status || 'idle';
    st.className = `pill ${j.status || 'idle'}`;
    $('btn-cancel').disabled = j.status !== 'running';
    $('btn-backup').disabled = $('btn-restore').disabled = j.status === 'running';
    if (j.status !== 'running' && j.status !== 'idle') {
      clearInterval(jobTimer); jobTimer = null;
      refreshSystem();
    }
  } catch {}
}
$('btn-cancel').onclick = async () => { try { await api('/api/job/cancel', { method: 'POST' }); } catch {} };
$('btn-refresh').onclick = refreshSystem;
$('btn-backup').onclick = () => openModal('modal-backup');
$('btn-restore').onclick = () => { $('rs-info').classList.add('hidden'); $('rs-start').disabled = true; openModal('modal-restore'); };
$('rs-mode').addEventListener('change', () => {
  $('rs-dc-extra').classList.toggle('hidden', $('rs-mode').value !== 'devcontainer');
});

// ---------------------------------------------------------------------------
// Modals
// ---------------------------------------------------------------------------
function openModal(id) { $(id).classList.remove('hidden'); }
function closeModal(id) { $(id).classList.add('hidden'); }
document.querySelectorAll('[data-close]').forEach(b =>
  b.onclick = () => b.closest('.modal').classList.add('hidden'));
document.querySelectorAll('.modal').forEach(m =>
  m.addEventListener('mousedown', (e) => { if (e.target === m) m.classList.add('hidden'); }));

// ---------------------------------------------------------------------------
// Backup flow
// ---------------------------------------------------------------------------
$('bk-start').onclick = async () => {
  const dest = $('bk-dest').value.trim();
  if (!dest) { alert('Choose a destination folder first.'); return; }
  const body = {
    destDir: dest,
    filename: $('bk-name').value.trim() || undefined,
    level: Number($('bk-level').value),
    includeNodeDist: $('bk-nodedist').checked,
    devcontainerKit: $('bk-dc').checked,
    includeLogs: $('bk-logs').checked,
  };
  try {
    await api('/api/backup', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    closeModal('modal-backup');
    showJob('Backup in progress');
  } catch (e) { alert(`Could not start backup: ${e.message}`); }
};

// ---------------------------------------------------------------------------
// Restore flow
// ---------------------------------------------------------------------------
let rsTimer = null;
$('rs-archive').addEventListener('input', () => {
  clearTimeout(rsTimer);
  rsTimer = setTimeout(loadArchiveInfo, 500);
});
async function loadArchiveInfo() {
  const p = $('rs-archive').value.trim();
  const box = $('rs-info');
  if (!p.toLowerCase().endsWith('.7z') || !p) { box.classList.add('hidden'); $('rs-start').disabled = true; return; }
  box.classList.remove('hidden');
  box.innerHTML = '<em>Reading archive manifest…</em>';
  try {
    const info = await api(`/api/archive-info?path=${encodeURIComponent(p)}`);
    if (info.error) { box.innerHTML = `⚠ ${info.error}`; $('rs-start').disabled = true; return; }
    const m = info.manifest || {};
    const row = (k, v) => `<tr><td>${k}</td><td>${v == null || v === '' ? '—' : v}</td></tr>`;
    box.innerHTML = `<table>
      ${row('Created', m.CREATED_UTC)}${row('Source host', m.HOSTNAME)}
      ${row('Ollama', m.OLLAMA_VERSION)}${row('Pi', m.PI_VERSION)}
      ${row('Node', `${m.NODE_VERSION || 'none'} (${m.NODE_MODE || '?'})`)}
      ${row('Models', m.MODELS_COUNT)}${row('Total size', humanSize(Number(m.SIZE_TOTAL_KB)))}
      ${row('Archive size', humanSize(info.sizeBytes / 1024))}
    </table>`;
    $('rs-start').disabled = false;
  } catch (e) { box.innerHTML = `⚠ ${e.message}`; $('rs-start').disabled = true; }
}
$('rs-start').onclick = async () => {
  const archive = $('rs-archive').value.trim();
  const mode = $('rs-mode').value;
  const target = mode === 'devcontainer'
    ? `Linux devcontainer (toolset only, OLLAMA_HOST=${$('rs-host').value.trim()})`
    : 'this machine (full restore incl. models)';
  if (!confirm(`Restore ${target} from:\n${archive}\n\nExisting installs will be moved aside. Continue?`)) return;
  try {
    const body = { archive, mode };
    if (mode === 'devcontainer') body.ollamaHost = $('rs-host').value.trim() || undefined;
    await api('/api/restore', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    closeModal('modal-restore');
    showJob(mode === 'devcontainer' ? 'Devcontainer restore in progress' : 'Restore in progress');
  } catch (e) { alert(`Could not start restore: ${e.message}`); }
};

// ---------------------------------------------------------------------------
// Server-backed file explorer
// ---------------------------------------------------------------------------
let exState = { mode: 'dir', target: null, selected: null };
document.querySelectorAll('[data-explorer]').forEach(btn => {
  btn.onclick = () => {
    exState = { mode: btn.dataset.mode, target: btn.dataset.explorer, selected: null };
    $('ex-title').textContent = btn.dataset.mode === 'file' ? 'Choose a backup archive (.7z)' : 'Choose a destination folder';
    $('ex-select').textContent = btn.dataset.mode === 'file' ? 'Select file' : 'Use this folder';
    $('ex-select').disabled = btn.dataset.mode === 'dir';
    const cur = $(btn.dataset.explorer).value.trim();
    openModal('modal-explorer');
    browse(cur || null);
  };
});
async function browse(path) {
  const list = $('ex-list');
  list.innerHTML = '<div class="ex-empty">Loading…</div>';
  try {
    const r = await api(`/api/browse?mode=${exState.mode}&path=${encodeURIComponent(path || '')}`);
    $('ex-path').value = r.path;
    exState.here = r.path; exState.parent = r.parent;
    exState.selected = null;
    $('ex-select').disabled = exState.mode === 'dir';
    list.innerHTML = r.entries.length ? '' : '<div class="ex-empty">Empty folder</div>';
    if (r.parent) {
      const up = document.createElement('div');
      up.className = 'exrow dir'; up.innerHTML = '<span class="nm">⋯ (parent)</span>';
      up.onclick = () => browse(r.parent);
      list.appendChild(up);
    }
    for (const e of r.entries) {
      const row = document.createElement('div');
      row.className = `exrow ${e.type}`;
      row.innerHTML = `<span class="nm">${e.name}</span><span class="sz">${e.type === 'file' ? humanSize(e.size / 1024) : ''}</span>`;
      row.onclick = () => {
        if (e.type === 'dir') { browse(r.path.replace(/\/$/, '') + '/' + e.name); return; }
        list.querySelectorAll('.exrow').forEach(x => x.classList.remove('selected'));
        row.classList.add('selected');
        exState.selected = r.path.replace(/\/$/, '') + '/' + e.name;
        $('ex-select').disabled = false;
      };
      row.ondblclick = () => { if (e.type === 'file') { exState.selected = r.path.replace(/\/$/, '') + '/' + e.name; pick(); } };
      list.appendChild(row);
    }
  } catch (e) { list.innerHTML = `<div class="ex-empty">${e.message}</div>`; }
}
function pick() {
  if (exState.mode === 'file' && exState.selected) {
    $(exState.target).value = exState.selected;
    $(exState.target).dispatchEvent(new Event('input'));
  } else if (exState.mode === 'dir' && exState.here) {
    $(exState.target).value = exState.here;
  }
  closeModal('modal-explorer');
}
$('ex-select').onclick = pick;
$('ex-go').onclick = () => browse($('ex-path').value.trim());
$('ex-up').onclick = () => browse(exState.parent || exState.here);
$('ex-path').addEventListener('keydown', (e) => { if (e.key === 'Enter') browse($('ex-path').value.trim()); });

// ---------------------------------------------------------------------------
refreshSystem();
