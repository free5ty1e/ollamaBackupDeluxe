#!/usr/bin/env node
/**
 * Ollama Backup Deluxe — web app server (zero npm dependencies).
 * Local-only UI wrapper around scripts/backup.sh and scripts/restore.sh.
 * Binds to 127.0.0.1 only. Run via start-webapp.sh (or: node webapp/server.js).
 */
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn, execFile } = require('child_process');

const PROJECT_DIR = path.resolve(__dirname, '..');
const SCRIPTS = path.join(PROJECT_DIR, 'scripts');
const PUBLIC = path.join(__dirname, 'public');
const LOG_DIR = path.join(PROJECT_DIR, 'logs');
const PORT = Number(process.env.OBD_PORT || 8686);
const HOST = '127.0.0.1';

fs.mkdirSync(LOG_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------
const sh = (cmd, args, opts = {}) =>
  new Promise((resolve) => {
    execFile(cmd, args, { timeout: opts.timeout || 30000, encoding: 'utf8' },
      (err, stdout, stderr) => resolve({ err, stdout: stdout || '', stderr: stderr || '' }));
  });
const exists = (p) => { try { fs.statSync(p); return true; } catch { return false; } };
const isDir = (p) => { try { return fs.statSync(p).isDirectory(); } catch { return false; } };
const json = (res, code, obj) => {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(body);
};
const readBody = (req) => new Promise((resolve, reject) => {
  let data = '';
  req.on('data', (c) => { data += c; if (data.length > 1e6) { reject(new Error('body too large')); req.destroy(); } });
  req.on('end', () => { try { resolve(data ? JSON.parse(data) : {}); } catch (e) { reject(e); } });
  req.on('error', reject);
});
const safePath = (p) => (typeof p === 'string' && p.length > 0 && !p.includes('\0') && path.isAbsolute(p)) ? p : null;

// ---------------------------------------------------------------------------
// 7zz resolution (mirrors scripts/common.sh order)
// ---------------------------------------------------------------------------
function find7zz() {
  const cands = [process.env.OBD_7ZZ, process.env.OBD_KIT_7ZZ,
    path.join(PROJECT_DIR, 'bin', `7zz-${process.arch === 'arm64' ? 'arm64' : 'x64'}`),
    path.join(PROJECT_DIR, 'bin', '7zz')].filter(Boolean);
  for (const c of cands) { try { fs.accessSync(c, fs.constants.X_OK); return c; } catch {} }
  for (const c of ['7zz', '7zzs', '7z']) {
    try { fs.accessSync(c, fs.constants.X_OK); return c; } catch {}
  }
  return null;
}

// ---------------------------------------------------------------------------
// System info (sizes cached 60 s — du on 61 GB is slow)
// ---------------------------------------------------------------------------
const sizeCache = new Map();
async function dirSize(p) {
  if (!isDir(p)) return null;
  const hit = sizeCache.get(p);
  if (hit && Date.now() - hit.at < 60000) return hit.kb;
  const r = await sh('/usr/bin/du', ['-sk', p], { timeout: 120000 });
  const kb = r.err ? null : parseInt(r.stdout.split('\t')[0], 10);
  sizeCache.set(p, { at: Date.now(), kb });
  return kb;
}
async function apiSystem() {
  const arch = process.arch === 'arm64' ? 'arm64' : 'x64';
  const home = process.env.HOME;
  const ollamaApp = '/Applications/Ollama.app';
  const ollamaHome = path.join(home, '.ollama');
  const piHome = path.join(home, '.pi');
  const appSupport = path.join(home, 'Library', 'Application Support', 'Ollama');
  const seven = find7zz();
  const [modelsKb, piKb] = await Promise.all([dirSize(ollamaHome), dirSize(piHome)]);
  let ollamaVersion = null;
  const ocli = path.join(ollamaApp, 'Contents/Resources/ollama');
  if (exists(ocli)) {
    const r = await sh(ocli, ['--version']);
    ollamaVersion = r.err ? 'present' : ((r.stdout.match(/is (\S+)/) || [])[1] || r.stdout.split('\n')[0].trim());
  }
  let piVersion = null;
  const piBin = path.join(piHome, 'agent/bin/pi');
  if (exists(piBin)) { const r = await sh(piBin, ['--version']); piVersion = r.err ? 'present' : r.stdout.trim().split('\n')[0]; }
  let nodeVersion = process.version;
  const opencodeHome = path.join(home, '.opencode');
  const claudeShare = path.join(home, '.local/share/claude');
  const claudeLauncher = path.join(home, '.local/bin/claude');
  let opencodeVersion = null;
  if (exists(path.join(opencodeHome, 'bin/opencode'))) {
    const r = await sh(path.join(opencodeHome, 'bin/opencode'), ['--version']);
    opencodeVersion = r.err ? 'present' : r.stdout.trim().split('\n')[0];
  }
  let claudeVersion = null;
  if (exists(claudeLauncher)) {
    const r = await sh(claudeLauncher, ['--version']);
    claudeVersion = r.err ? 'present' : (r.stdout.trim().split(' ')[0] || 'present');
  }
  const models = await sh('/usr/bin/find', [path.join(ollamaHome, 'models'), '-type', 'f', '-path', '*manifests*'], { timeout: 30000 });
  const modelCount = models.err ? 0 : models.stdout.split('\n').filter(l => l.includes('/manifests/') && !l.endsWith('/manifests')).length;
  const df = await sh('/bin/df', ['-k', PROJECT_DIR]);
  const freeKb = df.err ? null : parseInt(df.stdout.split('\n')[1].trim().split(/\s+/)[3], 10);
  return {
    project: PROJECT_DIR, port: PORT, arch,
    components: {
      ollamaApp: { path: ollamaApp, present: isDir(ollamaApp), version: ollamaVersion },
      ollamaHome: { path: ollamaHome, present: isDir(ollamaHome), sizeKb: modelsKb },
      ollamaAppSupport: { path: appSupport, present: isDir(appSupport) },
      pi: { path: piHome, present: isDir(piHome), version: piVersion, sizeKb: piKb },
      node: { version: nodeVersion },
      claude: { home: claudeShare, present: isDir(claudeShare), version: claudeVersion },
      opencode: { home: opencodeHome, present: isDir(opencodeHome), version: opencodeVersion },
      sevenZip: { path: seven, present: !!seven },
    },
    modelCount, diskFreeKb: freeKb,
  };
}

// ---------------------------------------------------------------------------
// File explorer API (server-backed — works in every browser, offline)
// ---------------------------------------------------------------------------
function apiBrowse(query) {
  const mode = query.get('mode') === 'file' ? 'file' : 'dir';
  const raw = query.get('path');
  const home = process.env.HOME || '/';
  let dir = (raw && safePath(raw)) ? raw : home;
  if (mode === 'file' && exists(dir) && !isDir(dir)) dir = path.dirname(dir);
  if (!isDir(dir)) dir = home;
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true })
      .filter(d => !d.name.startsWith('.'))
      .map(d => {
        let size = null;
        if (d.isFile()) { try { size = fs.statSync(path.join(dir, d.name)).size; } catch {} }
        return { name: d.name, type: d.isDirectory() ? 'dir' : 'file', size };
      })
      .sort((a, b) => (a.type === b.type ? a.name.localeCompare(b.name) : a.type === 'dir' ? -1 : 1));
    if (mode === 'file') entries = entries.filter(e => e.type === 'dir' || e.name.toLowerCase().endsWith('.7z'));
  } catch (e) {
    return { path: dir, parent: null, entries: [], error: String(e.message || e) };
  }
  const parent = path.dirname(dir) !== dir ? path.dirname(dir) : null;
  return { path: dir, parent, entries };
}

// ---------------------------------------------------------------------------
// Archive info (read manifest.env straight out of the .7z)
// ---------------------------------------------------------------------------
async function apiArchiveInfo(query) {
  const p = safePath(query.get('path'));
  if (!p || !exists(p) || isDir(p)) return { error: 'invalid archive path' };
  const seven = find7zz();
  if (!seven) return { error: '7zz not found — run scripts/prerequisites.sh' };
  const r = await sh(seven, ['e', '-y', '-bso0', '-ba', '-so', p, 'manifest.env'], { timeout: 60000 });
  if (r.err && !r.stdout) return { error: 'could not read manifest from archive (not an OBD kit?)' };
  const manifest = {};
  for (const line of r.stdout.split('\n')) {
    const m = line.match(/^([A-Z0-9_]+)="?(.*?)"?\s*$/);
    if (m) manifest[m[1]] = m[2];
  }
  const st = fs.statSync(p);
  return { path: p, sizeBytes: st.size, mtime: st.mtime.toISOString(), manifest };
}

// ---------------------------------------------------------------------------
// Job runner (single concurrent job; log tee'd to logs/)
// ---------------------------------------------------------------------------
let job = null;
function startJob(type, args) {
  if (job && job.status === 'running') return { error: 'another job is already running' };
  const id = Date.now().toString(36);
  const script = { backup: 'backup.sh', restore: 'restore.sh', 'restore-devcontainer': 'restore-devcontainer.sh', prereqs: 'prerequisites.sh' }[type] || 'prerequisites.sh';
  const logFile = path.join(LOG_DIR, `${new Date().toISOString().replace(/[:.]/g, '-')}-${type}.log`);
  const child = spawn('/bin/bash', [path.join(SCRIPTS, script), ...args], {
    env: { ...process.env, OBD_NONINTERACTIVE: '1' }, cwd: PROJECT_DIR,
  });
  const log = [];
  const stream = fs.createWriteStream(logFile);
  const push = (line) => {
    if (!line) return;
    log.push(line); if (log.length > 5000) log.splice(0, log.length - 5000);
    stream.write(line + '\n');
  };
  const feed = (buf) => String(buf).split(/[\r\n]+/).forEach(push);
  child.stdout.on('data', feed);
  child.stderr.on('data', feed);
  job = {
    id, type, status: 'running', exitCode: null, startedAt: new Date().toISOString(),
    endedAt: null, log, args, logFile,
    child,
    cancel() { try { child.kill('SIGTERM'); setTimeout(() => { try { child.kill('SIGKILL'); } catch {} }, 10000); } catch {} },
  };
  child.on('exit', (code, signal) => {
    job.status = signal === 'SIGTERM' ? 'canceled' : (code === 0 ? 'success' : 'error');
    job.exitCode = code; job.endedAt = new Date().toISOString();
    push(`[job finished: ${job.status}${code != null ? ` (exit ${code})` : ''}]`);
    stream.end();
  });
  return { id };
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  const p = url.pathname;
  try {
    if (p === '/api/system') return json(res, 200, await apiSystem());
    if (p === '/api/browse') return json(res, 200, apiBrowse(url.searchParams));
    if (p === '/api/archive-info') return json(res, 200, await apiArchiveInfo(url.searchParams));
    if (p === '/api/job') {
      const since = Number(url.searchParams.get('since') || 0);
      if (!job) return json(res, 200, { running: false, status: 'idle', log: [], total: 0 });
      return json(res, 200, {
        running: job.status === 'running', id: job.id, type: job.type, status: job.status,
        exitCode: job.exitCode, startedAt: job.startedAt, endedAt: job.endedAt,
        log: job.log.slice(since), total: job.log.length, logFile: job.logFile,
      });
    }
    if (p === '/api/job/cancel' && req.method === 'POST') {
      if (!job || job.status !== 'running') return json(res, 400, { error: 'no running job' });
      job.cancel(); return json(res, 200, { ok: true });
    }
    if (req.method === 'POST' && (p === '/api/backup' || p === '/api/restore' || p === '/api/prereqs')) {
      const body = p === '/api/prereqs' ? {} : await readBody(req);
      let args = [];
      if (p === '/api/backup') {
        const destDir = safePath(body.destDir);
        if (!destDir || !isDir(destDir)) return json(res, 400, { error: 'invalid destDir' });
        args = ['--dest', destDir, '--yes'];
        if (body.filename) args.push('--name', String(body.filename).replace(/[^\w.-]+/g, '_').slice(0, 120));
        const level = Number(body.level);
        if (Number.isInteger(level) && level >= 0 && level <= 9) args.push('--level', String(level));
        if (body.includeNodeDist === false) args.push('--no-node-dist');
        if (body.includeLogs === false) args.push('--no-logs');
        if (body.devcontainerKit === false) args.push('--no-devcontainer');
      } else if (p === '/api/restore') {
        const archive = safePath(body.archive);
        if (!archive || !exists(archive) || isDir(archive)) return json(res, 400, { error: 'invalid archive path' });
        if (body.mode === 'devcontainer') {
          args = ['--archive', archive, '--yes'];
          if (body.ollamaHost) args.push('--ollama-host', String(body.ollamaHost));
          const r = startJob('restore-devcontainer', args);
          return json(res, r.error ? 409 : 200, r);
        }
        args = ['--archive', archive, '--yes'];
      }
      const r = startJob(p.slice(5), args);
      return json(res, r.error ? 409 : 200, r);
    }
    // static files
    let file = p === '/' ? '/index.html' : p;
    file = path.normalize(file).replace(/^(\.\.[/\\])+/, '');
    const full = path.join(PUBLIC, file);
    if (!full.startsWith(PUBLIC) || !exists(full) || isDir(full)) { res.writeHead(404); return res.end('not found'); }
    const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
    res.writeHead(200, { 'Content-Type': types[path.extname(full)] || 'application/octet-stream' });
    fs.createReadStream(full).pipe(res);
  } catch (e) {
    json(res, 500, { error: String((e && e.message) || e) });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Ollama Backup Deluxe web app → http://${HOST}:${PORT}`);
});
