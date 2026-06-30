const API_BASE = window.location.origin;

async function apiRequest(method, path, body = null) {
  const options = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (body) options.body = JSON.stringify(body);

  const response = await fetch(`${API_BASE}${path}`, options);
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || `Request failed: ${response.status}`);
  return data;
}

const api = {
  health: () => apiRequest('GET', '/api/health'),
  getConfig: () => apiRequest('GET', '/api/config'),
  saveConfig: (config) => apiRequest('PUT', '/api/config', config),
  validateDownloadLocation: (path) => apiRequest('POST', '/api/config/validate-download-location', { path }),
  scanDownloadLinks: (url, appName) => apiRequest('POST', '/api/download/links', { url, appName }),
  download: (params) => apiRequest('POST', '/api/download', params),
  uploadInstaller: (params) => apiRequest('POST', '/api/installer/upload', params),
  analyzeInstaller: (installerPath) => apiRequest('POST', '/api/installer/analyze', { installerPath }),
  discoverSwitches: (params) => apiRequest('POST', '/api/installer/discover-switches', params),
  testSwitch: (params) => apiRequest('POST', '/api/installer/test-switch', params),
  buildPackage: (params) => apiRequest('POST', '/api/package', params),
};
