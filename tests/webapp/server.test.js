// test-webapp — zero-dependency tests for webapp/server.js using node:test.
// The server under test spawns the REAL backup.sh/restore.sh; OBD_* sandbox
// env vars are inherited, so jobs operate on fixture trees only.
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');

const ROOT = path.resolve(__dirname, '..', '..');
const TMP = path.join(ROOT, 'tests', '.tmp', 'webapp-test');

function req(port, method, apiPath, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request({ host: '127.0.0.1', port, path: apiPath, method,
      headers: data ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } : {} },
      (res) => {
        let buf = '';
        res.on('data', (c) => (buf += c));
        res.on('end', () => {
          let j = null; try { j = JSON.parse(buf); } catch {}
          resolve({ status: res.statusCode, text: buf, json: j });
        });
      });
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

function makeFixture(root) {
  fs.rmSync(root, { recursive: true, force: true });
  const oh = path.join(root, 'fake-home', '.ollama');
  fs.mkdirSync(path.join(oh, 'models/manifests/registry.ollama.ai/library/tiny'), { recursive: true });
  fs.mkdirSync(path.join(oh, 'models/blobs'), { recursive: true });
  fs.writeFileSync(path.join(oh, 'config.json'), '{}');
  fs.writeFileSync(path.join(oh, 'id_ed25519'), 'key');
  fs.writeFileSync(path.join(oh, 'models/blobs/sha256-' + 'a'.repeat(64)), 'weights');
  fs.writeFileSync(path.join(oh, 'models/manifests/registry.ollama.ai/library/tiny/1.0'), '{}');
  fs.mkdirSync(path.join(root, 'Applications/Ollama.app/Contents/Resources'), { recursive: true });
  fs.writeFileSync(path.join(root, 'Applications/Ollama.app/Contents/Resources/ollama'),
    '#!/bin/sh\n[ "$1" = "--version" ] && echo "ollama version is 0.99.0"\nexit 0\n', { mode: 0o755 });
}

let server = null, PORT = 0;
test.before(async () => {
  fs.mkdirSync(TMP, { recursive: true });
  makeFixture(path.join(TMP, 'fix'));
  makeFixture(path.join(TMP, 'dest-root')); // placeholder parent
  PORT = 18000 + Math.floor(Math.random() * 2000);
  server = spawn(process.execPath, [path.join(ROOT, 'webapp', 'server.js')], {
    env: {
      ...process.env, OBD_PORT: String(PORT), OBD_ALLOWED_ORIGIN: 'https://test.github.io',
      OBD_HOME: path.join(TMP, 'fix', 'fake-home'),
      OBD_OLLAMA_APP: path.join(TMP, 'fix', 'Applications', 'Ollama.app'),
      OBD_OLLAMA_HOME: path.join(TMP, 'fix', 'fake-home', '.ollama'),
      OBD_OLLAMA_APP_SUPPORT: path.join(TMP, 'fix', 'fake-home', 'Library', 'Application Support', 'Ollama'),
      OBD_PI_HOME: path.join(TMP, 'fix', 'fake-home', '.pi'),
      OBD_PI_LAUNCHER: path.join(TMP, 'fix', 'fake-home', '.local', 'bin', 'pi'),
      OBD_BREW_PREFIX: path.join(TMP, 'fix', 'brew'),
      OBD_NODE_BIN: path.join(TMP, 'fix', 'fake-node'), // mode=system (not under brew prefix)
      OBD_NO_QUIT: '1',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  server.stderr.on('data', (d) => process.env.OBD_DEBUG && console.error(String(d)));
  // wait for listen
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    try { await req(PORT, 'GET', '/api/system'); return; } catch { await new Promise(r => setTimeout(r, 200)); }
  }
  throw new Error('server did not start');
});
test.after(() => { try { server.kill('SIGKILL'); } catch {} });

test('GET / serves the UI', async () => {
  const r = await req(PORT, 'GET', '/');
  assert.equal(r.status, 200);
  assert.ok(r.text.includes('Ollama Backup Deluxe'));
});

test('GET /api/system returns component info', async () => {
  const r = await req(PORT, 'GET', '/api/system');
  assert.equal(r.status, 200);
  assert.ok(r.json.components, 'components object present');
  assert.ok(r.json.components.node.version, 'node version present');
  assert.ok(r.json.modelCount >= 0);
});

test('GET /api/browse dir mode lists entries', async () => {
  const dir = path.join(TMP, 'fix', 'fake-home', '.ollama');
  const r = await req(PORT, 'GET', `/api/browse?mode=dir&path=${encodeURIComponent(dir)}`);
  assert.equal(r.status, 200);
  const names = r.json.entries.map((e) => e.name);
  assert.ok(names.includes('models'));
  assert.ok(names.includes('config.json'));
});

test('GET /api/browse file mode filters to .7z', async () => {
  const dir = path.join(TMP, 'browse');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'kit.7z'), 'x');
  fs.writeFileSync(path.join(dir, 'notes.txt'), 'x');
  const r = await req(PORT, 'GET', `/api/browse?mode=file&path=${encodeURIComponent(dir)}`);
  const names = r.json.entries.map((e) => e.name);
  assert.ok(names.includes('kit.7z'));
  assert.ok(!names.includes('notes.txt'), 'non-7z hidden in file mode');
});

test('GET /api/browse rejects unsafe paths gracefully', async () => {
  const r = await req(PORT, 'GET', '/api/browse?path=relative/not/absolute');
  assert.equal(r.status, 200); // falls back to HOME
  assert.ok(r.json.path, 'has fallback path');
});

test('POST /api/backup runs the real backup script to completion', async () => {
  const dest = path.join(TMP, 'out');
  fs.mkdirSync(dest, { recursive: true });
  const start = await req(PORT, 'POST', '/api/backup',
    { destDir: dest, filename: 'webapp-test', level: 0 });
  assert.equal(start.status, 200, `start ok: ${JSON.stringify(start.json)}`);
  // poll job until finished
  const deadline = Date.now() + 120000;
  let job = null;
  while (Date.now() < deadline) {
    job = (await req(PORT, 'GET', '/api/job')).json;
    if (job.status !== 'running') break;
    await new Promise((r) => setTimeout(r, 400));
  }
  assert.equal(job.status, 'success', `job success; log tail: ${(job.log || []).slice(-8).join(' | ')}`);
  const archive = path.join(dest, 'webapp-test.7z');
  assert.ok(fs.existsSync(archive), 'archive file created');
  assert.ok(fs.existsSync(archive + '.sha256'), 'sha256 sidecar created');
  assert.ok(fs.existsSync(path.join(dest, 'webapp-test.manifest.txt')), 'manifest sidecar created');
  // manifest readable through archive-info
  const info = await req(PORT, 'GET', `/api/archive-info?path=${encodeURIComponent(archive)}`);
  assert.equal(info.status, 200);
  assert.equal(info.json.manifest.OLLAMA_VERSION, '0.99.0');
  assert.equal(info.json.manifest.MODELS_COUNT, '1');
});

test('POST /api/job/cancel with no running job → 400', async () => {
  const r = await req(PORT, 'POST', '/api/job/cancel');
  assert.equal(r.status, 400);
});

test('CORS: allowed origin echoed on API + preflight works', async () => {
  const r = await req(PORT, 'GET', '/api/system');
  assert.equal(r.status, 200);
  const headers = await new Promise((resolve, reject) => {
    const rq = http.request({ host: '127.0.0.1', port: PORT, path: '/api/system', method: 'GET' }, (res) => resolve(res.headers));
    rq.on('error', reject); rq.end();
  });
  assert.equal(headers['access-control-allow-origin'], 'https://test.github.io');
  const pre = await new Promise((resolve, reject) => {
    const rq = http.request({ host: '127.0.0.1', port: PORT, path: '/api/system', method: 'OPTIONS' }, (res) => resolve(res));
    rq.on('error', reject); rq.end();
  });
  assert.equal(pre.statusCode, 204);
  assert.equal(pre.headers['access-control-allow-methods'], 'GET, POST');
});

test('Static UI: relative assets + guide markup present (Pages-compatible)', async () => {
  const r = await req(PORT, 'GET', '/');
  assert.ok(r.text.includes('href="style.css"'), 'stylesheet referenced relatively');
  assert.ok(r.text.includes('src="app.js"'), 'app.js referenced relatively');
  assert.ok(r.text.includes('id="guide-panel"'), 'guide panel present');
  assert.ok(r.text.includes('id="connected-banner"'), 'connected banner present');
});

test('GET /api/archive-info on non-archive → error field', async () => {
  const bogus = path.join(TMP, 'bogus.7z');
  fs.writeFileSync(bogus, 'not a 7z file');
  const r = await req(PORT, 'GET', `/api/archive-info?path=${encodeURIComponent(bogus)}`);
  assert.equal(r.status, 200);
  assert.ok(r.json.error, 'error reported');
});
