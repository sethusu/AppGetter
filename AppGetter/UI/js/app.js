let currentConfig = {};
let lastInstallerPath = '';

document.addEventListener('DOMContentLoaded', async () => {
  initNavigation();
  initDownloadPage();
  initSwitchPage();
  initPackagePage();
  initSettingsPage();
  await checkApiAndLoadConfig();
});

function initNavigation() {
  document.querySelectorAll('.nav-btn').forEach(btn => {
    btn.addEventListener('click', () => navigateTo(btn.dataset.page));
  });
}

function navigateTo(page) {
  document.querySelectorAll('.nav-btn').forEach(b => b.classList.toggle('active', b.dataset.page === page));
  document.querySelectorAll('.page').forEach(p => p.classList.toggle('active', p.id === `page-${page}`));
}

async function checkApiAndLoadConfig() {
  const statusEl = document.getElementById('apiStatus');
  try {
    await api.health();
    statusEl.innerHTML = '<span class="status-dot online"></span><span>Connected</span>';
    currentConfig = await api.getConfig();
    updateConfigSummary();
    populateSettingsForm();
  } catch {
    statusEl.innerHTML = '<span class="status-dot offline"></span><span>API Offline</span>';
    showToast('Cannot connect to AppGetter API. Start the backend with Start-AppGetter.ps1', 'error');
  }
}

function updateConfigSummary() {
  const el = document.getElementById('configSummary');
  if (!el || !currentConfig.downloadLocation) return;
  el.innerHTML = `
    <strong>Current Configuration</strong><br>
    Download Location: <code>${esc(currentConfig.downloadLocation)}</code><br>
    Package Output: <code>${esc(currentConfig.outputPath)}</code><br>
    Switch Test Mode: <code>${esc(currentConfig.switchTestMode || 'dry-run')}</code>
  `;
}

function populateSettingsForm() {
  if (!currentConfig) return;
  setVal('cfgDownloadLocation', currentConfig.downloadLocation);
  setVal('cfgOutputPath', currentConfig.outputPath);
  setVal('cfgApiPort', currentConfig.apiPort);
  setVal('cfgSwitchTestMode', currentConfig.switchTestMode || 'dry-run');
  document.getElementById('cfgAutoOpenBrowser').checked = currentConfig.autoOpenBrowser !== false;
}

/* Download Page */
function initDownloadPage() {
  let sourceType = 'direct';

  document.querySelectorAll('.seg-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.seg-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      sourceType = btn.dataset.source;
      document.getElementById('directUrlRow').classList.toggle('hidden', sourceType !== 'direct');
      document.getElementById('websiteUrlRow').classList.toggle('hidden', sourceType !== 'website');
      document.getElementById('localPathRow').classList.toggle('hidden', sourceType !== 'local');
    });
  });

  document.getElementById('btnScanLinks').addEventListener('click', async () => {
    const url = getVal('dlWebsite');
    const appName = getVal('dlAppName');
    if (!url) return showToast('Enter a website URL', 'error');

    const btn = document.getElementById('btnScanLinks');
    btn.disabled = true;
    btn.innerHTML = '<span class="loading"></span> Scanning...';

    try {
      const result = await api.scanDownloadLinks(url, appName);
      const select = document.getElementById('dlLinkSelect');
      select.innerHTML = result.links.map((l, i) => `<option value="${esc(l)}">${esc(l)}</option>`).join('');
      document.getElementById('linkSelectRow').classList.toggle('hidden', result.count === 0);
      showToast(`Found ${result.count} download link(s)`, result.count ? 'success' : 'info');
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Scan for Links';
    }
  });

  document.getElementById('btnDownload').addEventListener('click', async () => {
    const appName = getVal('dlAppName');
    if (!appName) return showToast('Application name is required', 'error');

    const btn = document.getElementById('btnDownload');
    btn.disabled = true;
    btn.innerHTML = '<span class="loading"></span> Working...';
    const resultEl = document.getElementById('downloadResult');

    try {
      let result;
      if (sourceType === 'local') {
        const localPath = getVal('dlLocalPath');
        if (!localPath) return showToast('Enter a local file path', 'error');
        result = await api.uploadInstaller({
          sourcePath: localPath,
          appName,
          version: getVal('dlVersion') || 'latest',
        });
      } else {
        let url = getVal('dlUrl');
        if (sourceType === 'website') {
          const select = document.getElementById('dlLinkSelect');
          url = select.value || getVal('dlWebsite');
        }
        if (!url) return showToast('Enter a download URL', 'error');
        result = await api.download({
          url,
          appName,
          version: getVal('dlVersion') || 'latest',
        });
      }

      lastInstallerPath = result.path;
      resultEl.classList.remove('hidden', 'error');
      resultEl.classList.add('success');
      resultEl.innerHTML = `
        <strong>Success!</strong><br>
        File: <code>${esc(result.fileName || result.path)}</code><br>
        Path: <code>${esc(result.path)}</code><br>
        Size: ${result.sizeMB || 'N/A'} MB<br>
        ${result.hash ? `SHA256: <code>${esc(result.hash)}</code>` : ''}
      `;
      setVal('swInstallerPath', result.path);
      setVal('pkgInstallerPath', result.path);
      setVal('swAppName', appName);
      setVal('pkgAppName', appName);
      showToast('Installer ready for analysis', 'success');
    } catch (e) {
      resultEl.classList.remove('hidden', 'success');
      resultEl.classList.add('error');
      resultEl.textContent = e.message;
      showToast(e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Download / Import';
    }
  });
}

/* Switch Discovery Page */
function initSwitchPage() {
  document.getElementById('btnQuickAnalyze').addEventListener('click', async () => {
    const path = getVal('swInstallerPath');
    if (!path) return showToast('Enter installer path', 'error');

    try {
      const result = await api.analyzeInstaller(path);
      renderSwitchResults({
        installerType: result.installerType,
        status: result.status,
        switches: result.switches,
        recommendedCommand: result.installCommandTemplate,
        tests: [],
      });
      showToast(`Installer type: ${result.installerType.displayName}`, 'info');
    } catch (e) {
      showToast(e.message, 'error');
    }
  });

  document.getElementById('btnDiscoverSwitches').addEventListener('click', async () => {
    const path = getVal('swInstallerPath');
    if (!path) return showToast('Enter installer path', 'error');

    const btn = document.getElementById('btnDiscoverSwitches');
    btn.disabled = true;
    btn.innerHTML = '<span class="loading"></span> Discovering...';

    try {
      const result = await api.discoverSwitches({
        installerPath: path,
        supportUrl: getVal('swSupportUrl'),
        appName: getVal('swAppName'),
        testMode: getVal('swTestMode'),
      });
      renderSwitchResults(result);
      setVal('pkgInstallCommand', result.recommendedCommand);
      showToast(`Found ${result.switchCount} switch(es) - Status: ${result.status}`, 'success');
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Discover Switches';
    }
  });
}

function renderSwitchResults(result) {
  document.getElementById('switchResults').classList.remove('hidden');

  const statusEl = document.getElementById('switchStatus');
  const statusClass = result.status === 'known' ? 'known' :
    result.status === 'discovered' ? 'discovered' : 'unknown';
  statusEl.className = `status-badge ${statusClass}`;
  statusEl.textContent = result.status === 'known' ? 'Known Switches' :
    result.status === 'discovered' ? 'Switches Discovered' :
    result.needsManualDiscovery ? 'Manual Discovery Needed' : 'Unknown';

  const typeCard = document.getElementById('installerTypeCard');
  const it = result.installerType;
  typeCard.innerHTML = `
    <h3>${esc(it.displayName || 'Unknown')}</h3>
    <p>Framework: <strong>${esc(it.framework)}</strong> | Confidence: <strong>${esc(it.confidence)}</strong></p>
    ${it.signatures?.length ? `<p>Signatures: ${it.signatures.map(esc).join(', ')}</p>` : ''}
  `;

  const tbody = document.querySelector('#switchesTable tbody');
  tbody.innerHTML = (result.switches || []).map(sw => `
    <tr>
      <td><code>${esc(sw.switch)}</code></td>
      <td class="confidence-${sw.confidence}">${esc(sw.confidence)}</td>
      <td>${esc(sw.source)}</td>
      <td>${esc(sw.description || sw.context || '')}</td>
      <td><button class="btn btn-sm secondary" onclick="testSingleSwitch('${esc(sw.switch)}')">Test</button></td>
    </tr>
  `).join('');

  document.getElementById('recommendedCommand').innerHTML = `
    <strong>Recommended Install Command</strong>
    ${esc(result.recommendedCommand || '')}
  `;

  const testEl = document.getElementById('testResults');
  testEl.innerHTML = (result.tests || []).map(t => `
    <div class="result-panel ${t.success ? 'success' : ''}">
      Switch: <code>${esc(t.switch)}</code> | Mode: ${esc(t.mode)} |
      ${t.success ? 'Pass' : 'Fail'} | ${esc(t.message)}
    </div>
  `).join('') || '<p class="field-hint">No tests run yet</p>';
}

async function testSingleSwitch(switchStr) {
  const path = getVal('swInstallerPath');
  try {
    const result = await api.testSwitch({
      installerPath: path,
      switch: switchStr,
      mode: getVal('swTestMode'),
    });
    showToast(`${switchStr}: ${result.message}`, result.success ? 'success' : 'error');
  } catch (e) {
    showToast(e.message, 'error');
  }
}

/* Package Page */
function initPackagePage() {
  document.getElementById('btnAutoDetectCommand').addEventListener('click', async () => {
    const path = getVal('pkgInstallerPath');
    if (!path) return showToast('Enter installer path', 'error');
    try {
      const result = await api.discoverSwitches({
        installerPath: path,
        appName: getVal('pkgAppName'),
        testMode: 'dry-run',
      });
      setVal('pkgInstallCommand', result.recommendedCommand);
      showToast('Install command auto-detected', 'success');
    } catch (e) {
      showToast(e.message, 'error');
    }
  });

  document.getElementById('btnBuildPackage').addEventListener('click', async () => {
    const appName = getVal('pkgAppName');
    const installerPath = getVal('pkgInstallerPath');
    if (!appName || !installerPath) return showToast('App name and installer path required', 'error');

    const btn = document.getElementById('btnBuildPackage');
    btn.disabled = true;
    btn.innerHTML = '<span class="loading"></span> Building...';
    const resultEl = document.getElementById('packageResult');

    try {
      let installCommand = getVal('pkgInstallCommand');
      if (!installCommand) {
        const discovery = await api.discoverSwitches({ installerPath, appName, testMode: 'dry-run' });
        installCommand = discovery.recommendedCommand;
      }

      const result = await api.buildPackage({
        appName,
        installerPath,
        installCommand,
        version: getVal('pkgVersion') || 'latest',
        publisher: getVal('pkgPublisher'),
        skipIntuneWin: document.getElementById('pkgSkipIntuneWin').checked,
      });

      resultEl.classList.remove('hidden', 'error');
      resultEl.classList.add('success');
      resultEl.innerHTML = `
        <strong>Package Created!</strong><br>
        Package ID: <code>${esc(result.packageId)}</code><br>
        Output: <code>${esc(result.outputDirectory)}</code><br>
        Install Command: <code>${esc(result.installCommand)}</code><br>
        ${result.intunewinFile ? `IntuneWin: <code>${esc(result.intunewinFile)}</code>` : 'IntuneWin: skipped'}
      `;
      showToast('Package built successfully', 'success');
    } catch (e) {
      resultEl.classList.remove('hidden', 'success');
      resultEl.classList.add('error');
      resultEl.textContent = e.message;
      showToast(e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Build Package';
    }
  });
}

/* Settings Page */
function initSettingsPage() {
  document.getElementById('btnValidateDownload').addEventListener('click', async () => {
    const path = getVal('cfgDownloadLocation');
    try {
      const result = await api.validateDownloadLocation(path);
      const el = document.getElementById('validationResult');
      el.classList.remove('hidden', 'valid', 'invalid');
      el.classList.add(result.valid ? 'valid' : 'invalid');
      el.textContent = result.valid
        ? `${result.message} (${result.freeSpaceGB} GB free)`
        : result.message;
    } catch (e) {
      showToast(e.message, 'error');
    }
  });

  document.getElementById('btnSaveSettings').addEventListener('click', async () => {
    try {
      currentConfig = await api.saveConfig({
        downloadLocation: getVal('cfgDownloadLocation'),
        outputPath: getVal('cfgOutputPath'),
        apiPort: parseInt(getVal('cfgApiPort'), 10),
        switchTestMode: getVal('cfgSwitchTestMode'),
        autoOpenBrowser: document.getElementById('cfgAutoOpenBrowser').checked,
      });
      updateConfigSummary();
      showToast('Settings saved', 'success');
    } catch (e) {
      showToast(e.message, 'error');
    }
  });
}

/* Utilities */
function getVal(id) { return document.getElementById(id).value.trim(); }
function setVal(id, val) { document.getElementById(id).value = val || ''; }

function esc(str) {
  if (!str) return '';
  const d = document.createElement('div');
  d.textContent = str;
  return d.innerHTML;
}

function showToast(message, type = 'info') {
  const container = document.getElementById('toastContainer');
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => toast.remove(), 4000);
}

window.navigateTo = navigateTo;
window.testSingleSwitch = testSingleSwitch;
