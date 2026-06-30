const statusLine = document.getElementById("statusLine");
const resultPanel = document.getElementById("resultPanel");
const installerPathInput = document.getElementById("installerPath");

function setStatus(message, isError = false) {
  statusLine.textContent = message;
  statusLine.style.color = isError ? "#ffb4b4" : "#cbdaff";
}

function setResult(payload) {
  resultPanel.textContent = JSON.stringify(payload, null, 2);
  if (payload?.installer_path) {
    installerPathInput.value = payload.installer_path;
  }
}

async function callApi(path, options = {}) {
  const response = await fetch(path, options);
  let body;
  try {
    body = await response.json();
  } catch (error) {
    body = { message: "Response did not contain JSON." };
  }
  if (!response.ok) {
    throw new Error(body.detail || body.message || `Request failed: ${response.status}`);
  }
  return body;
}

async function bootstrapConfig() {
  try {
    const config = await callApi("/api/config");
    document.getElementById("downloadLocation").value = config.download_location;
    document.getElementById("outputPath").value = config.download_location;
    setStatus("Config loaded.");
  } catch (error) {
    setStatus(error.message, true);
  }
}

document.getElementById("saveConfigBtn").addEventListener("click", async () => {
  const download_location = document.getElementById("downloadLocation").value.trim();
  if (!download_location) {
    setStatus("Download location is required.", true);
    return;
  }
  setStatus("Saving download location...");
  try {
    const payload = await callApi("/api/config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ download_location }),
    });
    setResult(payload);
    setStatus("Download location updated.");
  } catch (error) {
    setStatus(error.message, true);
  }
});

document.getElementById("analyzeUrlBtn").addEventListener("click", async () => {
  const downloadUrl = document.getElementById("downloadUrl").value.trim();
  const downloadLocation = document.getElementById("downloadLocation").value.trim();
  const try_runtime_tests = document.getElementById("runtimeProbeForUrl").checked;
  if (!downloadUrl) {
    setStatus("Installer URL is required.", true);
    return;
  }

  setStatus("Downloading and analyzing installer...");
  try {
    const payload = await callApi("/api/analyze/url", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        download_url: downloadUrl,
        download_location: downloadLocation || null,
        try_runtime_tests,
      }),
    });
    setResult(payload);
    setStatus("Installer analyzed from URL.");
  } catch (error) {
    setStatus(error.message, true);
  }
});

document.getElementById("analyzeUploadBtn").addEventListener("click", async () => {
  const fileInput = document.getElementById("uploadFile");
  const file = fileInput.files?.[0];
  const downloadLocation = document.getElementById("downloadLocation").value.trim();
  const try_runtime_tests = document.getElementById("runtimeProbeForUpload").checked;

  if (!file) {
    setStatus("Select an installer file first.", true);
    return;
  }

  const formData = new FormData();
  formData.append("file", file);
  if (downloadLocation) {
    formData.append("download_location", downloadLocation);
  }
  formData.append("try_runtime_tests", String(try_runtime_tests));

  setStatus("Uploading and analyzing installer...");
  try {
    const payload = await callApi("/api/analyze/upload", {
      method: "POST",
      body: formData,
    });
    setResult(payload);
    setStatus("Installer analyzed from upload.");
  } catch (error) {
    setStatus(error.message, true);
  }
});

document.getElementById("discoverBtn").addEventListener("click", async () => {
  const installerPath = installerPathInput.value.trim();
  const try_runtime_tests = document.getElementById("runtimeProbeForDiscover").checked;
  if (!installerPath) {
    setStatus("Installer path is required.", true);
    return;
  }

  setStatus("Discovering silent switches...");
  try {
    const payload = await callApi("/api/discover-switches", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ installer_path: installerPath, try_runtime_tests }),
    });
    setResult(payload);
    setStatus("Switch discovery completed.");
  } catch (error) {
    setStatus(error.message, true);
  }
});

document.getElementById("buildPackageBtn").addEventListener("click", async () => {
  const payload = {
    app_name: document.getElementById("appName").value.trim(),
    publisher: document.getElementById("publisher").value.trim() || null,
    website_url: document.getElementById("websiteUrl").value.trim() || null,
    download_url: document.getElementById("packageDownloadUrl").value.trim() || null,
    version: document.getElementById("version").value.trim() || null,
    output_path: document.getElementById("outputPath").value.trim() || null,
    install_command: document.getElementById("installCommand").value.trim() || null,
    icon_path: document.getElementById("iconPath").value.trim() || null,
  };

  if (!payload.app_name) {
    setStatus("App name is required for package creation.", true);
    return;
  }
  if (!payload.website_url && !payload.download_url) {
    setStatus("Provide at least website URL or download URL.", true);
    return;
  }

  setStatus("Running Create-IntuneWinFromWeb.ps1...");
  try {
    const result = await callApi("/api/create-package", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    setResult(result);
    setStatus(
      result.success
        ? "Package script completed successfully."
        : "Script completed with non-zero exit code."
    );
  } catch (error) {
    setStatus(error.message, true);
  }
});

bootstrapConfig();

