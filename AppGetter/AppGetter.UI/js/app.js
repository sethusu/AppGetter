const API = '/api';

// --- Utilities ---

async function api(method, path, body) {
  const opts = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`${API}${path}`, opts);
  const data = await res.json();
  if (!res.ok || data.success === false) {
    throw new Error(data.error || `Request failed (${res.status})`);
  }
  return data;
}

function toast(message, duration = 3000) {
  const container = document.getElementById('toastContainer');
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = message;
  container.appendChild(el);
  setTimeout(() => el.remove(), duration);
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(2)} MB`;
}

function showResult(elId, message, isError = false) {
  const el = document.getElementById(elId);
  el.className = `result-panel ${isError ? 'error' : 'success'}`;
  el.textContent = message;
  el.classList.remove('hidden');
}

// --- Navigation ---

document.querySelectorAll('.nav-item').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.nav-item').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById(`page-${btn.dataset.page}`).classList.add('active');
    if (btn.dataset.page === 'dashboard') loadDashboard();
    if (btn.dataset.page === 'analyze' || btn.dataset.page === 'discover') loadInstallerList();
  });
});

// --- Server health ---

async function checkHealth() {
  const dot = document.getElementById('serverStatus');
  const text = document.getElementById('serverStatusText');
  try {
    const data = await api('GET', '/health');
    dot.className = 'status-dot online';
    text.textContent = `v${data.version} — Online`;
  } catch {
    dot.className = 'status-dot offline';
    text.textContent = 'Offline';
  }
}

// --- Config ---

let currentConfig = {};

async function loadConfig() {
  const data = await api('GET', '/config');
  currentConfig = data.config;
  populateSettings(data.config);
  return data.config;
}

function populateSettings(cfg) {
  document.getElementById('settingDownloadLocation').value = cfg.DownloadLocation || '';
  document.getElementById('settingOutputPath').value = cfg.OutputPath || '';
  document.getElementById('settingSupportUrl').value = cfg.SupportUrl || '';
  document.getElementById('settingDeveloperUrl').value = cfg.DeveloperUrl || '';
  document.getElementById('settingServerPort').value = cfg.ServerPort || 8765;
  document.getElementById('settingAutoDiscover').checked = cfg.AutoDiscoverSwitches !== false;
  document.getElementById('settingTestInstallers').checked = cfg.TestInstallers !== false;
  document.getElementById('discoverSupportUrl').value = cfg.SupportUrl || '';
}

document.getElementById('btnSaveSettings').addEventListener('click', async () => {
  try {
    const body = {
      downloadLocation: document.getElementById('settingDownloadLocation').value,
      outputPath: document.getElementById('settingOutputPath').value,
      supportUrl: document.getElementById('settingSupportUrl').value,
      developerUrl: document.getElementById('settingDeveloperUrl').value,
      serverPort: parseInt(document.getElementById('settingServerPort').value, 10),
      autoDiscoverSwitches: document.getElementById('settingAutoDiscover').checked,
      testInstallers: document.getElementById('settingTestInstallers').checked,
    };
    const data = await api('PUT', '/config', body);
    currentConfig = data.config;
    showResult('settingsResult', 'Settings saved successfully.');
    toast('Settings saved');
    loadDashboard();
  } catch (err) {
    showResult('settingsResult', err.message, true);
  }
});

// --- Dashboard ---

async function loadDashboard() {
  try {
    const cfg = currentConfig.DownloadLocation ? currentConfig : await loadConfig();
    document.getElementById('dashDownloadPath').textContent = cfg.DownloadLocation || '—';
    document.getElementById('dashAutoDiscover').textContent = cfg.AutoDiscoverSwitches !== false ? 'Enabled' : 'Disabled';

    const data = await api('GET', '/installers');
    const installers = data.installers || [];
    document.getElementById('dashInstallerCount').textContent = installers.length;

    const container = document.getElementById('recentInstallers');
    if (installers.length === 0) {
      container.innerHTML = '<p class="empty-state">No installers found. Download or upload one to get started.</p>';
      return;
    }

    container.innerHTML = installers.map(i => `
      <div class="installer-item">
        <div>
          <div class="installer-name">${escapeHtml(i.name)}</div>
          <div class="installer-meta">${formatBytes(i.sizeBytes)} — ${new Date(i.modified).toLocaleString()}</div>
        </div>
      </div>
    `).join('');
  } catch (err) {
    console.error('Dashboard load failed:', err);
  }
}

// --- Installer list (shared) ---

async function loadInstallerList() {
  try {
    const data = await api('GET', '/installers');
    const installers = data.installers || [];
    const options = '<option value="">— Select an installer —</option>' +
      installers.map(i => `<option value="${escapeAttr(i.path)}">${escapeHtml(i.name)} (${formatBytes(i.sizeBytes)})</option>`).join('');

    document.getElementById('analyzeInstaller').innerHTML = options;
    document.getElementById('discoverInstaller').innerHTML = options;
  } catch (err) {
    console.error('Installer list load failed:', err);
  }
}

// --- Download ---

document.getElementById('btnScanLinks').addEventListener('click', async () => {
  const url = document.getElementById('websiteUrl').value;
  if (!url) { toast('Enter a website URL to scan'); return; }
  try {
    const data = await api('POST', '/download-links', { url });
    const container = document.getElementById('linkResults');
    if (data.links.length === 0) {
      container.innerHTML = '<p class="empty-state">No download links found.</p>';
    } else {
      container.innerHTML = data.links.map(link =>
        `<div class="link-item" data-url="${escapeAttr(link)}">${escapeHtml(link)}</div>`
      ).join('');
      container.querySelectorAll('.link-item').forEach(el => {
        el.addEventListener('click', () => {
          document.getElementById('downloadUrl').value = el.dataset.url;
          toast('URL selected');
        });
      });
    }
    container.classList.remove('hidden');
  } catch (err) {
    toast(err.message);
  }
});

document.getElementById('btnDownload').addEventListener('click', async () => {
  const url = document.getElementById('downloadUrl').value;
  if (!url) { toast('Enter a download URL'); return; }
  const btn = document.getElementById('btnDownload');
  btn.disabled = true;
  btn.textContent = 'Downloading...';
  try {
    const body = { url };
    const fileName = document.getElementById('downloadFileName').value;
    if (fileName) body.fileName = fileName;
    const data = await api('POST', '/download', body);
    showResult('downloadResult', `Downloaded ${data.download.fileName} (${formatBytes(data.download.sizeBytes)}) to ${data.download.filePath}`);
    toast('Download complete');
    loadInstallerList();
  } catch (err) {
    showResult('downloadResult', err.message, true);
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<svg viewBox="0 0 24 24" fill="currentColor" width="18" height="18"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg> Download';
  }
});

// --- Upload ---

const uploadZone = document.getElementById('uploadZone');
const fileUpload = document.getElementById('fileUpload');

uploadZone.addEventListener('click', () => fileUpload.click());
uploadZone.addEventListener('dragover', e => { e.preventDefault(); uploadZone.classList.add('dragover'); });
uploadZone.addEventListener('dragleave', () => uploadZone.classList.remove('dragover'));
uploadZone.addEventListener('drop', e => {
  e.preventDefault();
  uploadZone.classList.remove('dragover');
  if (e.dataTransfer.files.length) uploadFile(e.dataTransfer.files[0]);
});
fileUpload.addEventListener('change', () => {
  if (fileUpload.files.length) uploadFile(fileUpload.files[0]);
});

async function uploadFile(file) {
  try {
    const res = await fetch(`${API}/upload?filename=${encodeURIComponent(file.name)}`, {
      method: 'POST',
      body: file,
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    showResult('uploadResult', `Uploaded ${data.fileName} successfully.`);
    toast('Upload complete');
    loadInstallerList();
  } catch (err) {
    showResult('uploadResult', err.message, true);
  }
}

// --- Analyze ---

document.getElementById('btnAnalyze').addEventListener('click', async () => {
  const path = document.getElementById('analyzeInstaller').value;
  if (!path) { toast('Select an installer'); return; }
  const btn = document.getElementById('btnAnalyze');
  btn.disabled = true;
  btn.textContent = 'Analyzing...';
  try {
    const data = await api('POST', '/analyze', { installerPath: path });
    renderAnalyzeResult(data);
    document.getElementById('analyzeResult').classList.remove('hidden');
  } catch (err) {
    toast(err.message);
  } finally {
    btn.disabled = false;
    btn.textContent = 'Test Silent Switches';
  }
});

function renderAnalyzeResult(data) {
  const info = data.info;
  const test = data.switchTest;

  document.getElementById('analyzeInfo').innerHTML = [
    ['File', info.FileName],
    ['Type', info.InstallerType],
    ['Size', `${info.SizeMB} MB`],
    ['SHA-256', info.Sha256?.substring(0, 16) + '...'],
    ['Signature', info.KnownSignature || 'None'],
  ].map(([label, value]) => detailRow(label, value)).join('');

  const statusClass = test.Status === 'known' ? 'known' : 'needs-discovery';
  document.getElementById('analyzeStatus').innerHTML = [
    ['Status', `<span class="badge ${statusClass}">${test.Status}</span>`],
    ['Source', test.Source],
    ['Needs Discovery', test.NeedsDiscovery ? 'Yes' : 'No'],
    ['Recommended', test.RecommendedCommand || '—'],
  ].map(([label, value]) => detailRow(label, value)).join('');

  const candidates = test.Candidates || [];
  if (candidates.length === 0) {
    document.getElementById('analyzeCandidatesCard').classList.add('hidden');
  } else {
    document.getElementById('analyzeCandidatesCard').classList.remove('hidden');
    document.getElementById('analyzeCandidates').innerHTML = candidates.map(c => `
      <div class="candidate-row">
        <span><code>${escapeHtml(c.Switch)}</code></span>
        <span>${escapeHtml(c.Source)}</span>
        <span class="badge ${c.Confidence}">${c.Confidence}</span>
      </div>
    `).join('');
  }
}

// --- Discover ---

document.getElementById('btnDiscover').addEventListener('click', async () => {
  const path = document.getElementById('discoverInstaller').value;
  if (!path) { toast('Select an installer'); return; }
  const btn = document.getElementById('btnDiscover');
  btn.disabled = true;
  btn.textContent = 'Discovering...';
  try {
    const body = {
      installerPath: path,
      appName: document.getElementById('discoverAppName').value,
      supportUrl: document.getElementById('discoverSupportUrl').value,
      skipProbe: document.getElementById('discoverSkipProbe').checked,
      skipWebResearch: document.getElementById('discoverSkipWeb').checked,
    };
    const data = await api('POST', '/discover-switches', body);
    renderDiscoverResult(data.discovery);
    document.getElementById('discoverResult').classList.remove('hidden');
    toast('Discovery complete');
  } catch (err) {
    toast(err.message);
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<svg viewBox="0 0 24 24" fill="currentColor" width="18" height="18"><path d="M15.5 14h-.79l-.28-.27A6.471 6.471 0 0016 9.5 6.5 6.5 0 109.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5z"/></svg> Discover Switches';
  }
});

function renderDiscoverResult(d) {
  document.getElementById('discoverCommand').textContent = d.RecommendedCommand || 'No command determined';
  const conf = document.getElementById('discoverConfidence');
  conf.textContent = d.Confidence || 'unknown';
  conf.className = `badge ${d.Confidence || 'unknown'}`;

  document.getElementById('discoverMethods').innerHTML = (d.Methods || []).map(m =>
    `<span class="tag">${escapeHtml(m)}</span>`
  ).join('') || '<span class="empty-state">No methods used</span>';

  document.getElementById('discoverCandidates').innerHTML = (d.Candidates || []).map(c => `
    <div class="candidate-row">
      <span><code>${escapeHtml(c.Switch)}</code></span>
      <span>${escapeHtml(c.Source)}</span>
      <span class="badge ${c.Confidence}">${c.Confidence}</span>
    </div>
  `).join('') || '<p class="empty-state">No candidates found</p>';
}

document.getElementById('btnCopyCommand').addEventListener('click', () => {
  const cmd = document.getElementById('discoverCommand').textContent;
  navigator.clipboard.writeText(cmd).then(() => toast('Copied to clipboard'));
});

// --- Helpers ---

function detailRow(label, value) {
  return `<div class="detail-row"><span class="detail-label">${label}</span><span class="detail-value">${value}</span></div>`;
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

function escapeAttr(str) {
  return str.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// --- Init ---

(async () => {
  await checkHealth();
  await loadConfig();
  await loadDashboard();
  setInterval(checkHealth, 30000);
})();
