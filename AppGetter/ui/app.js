const downloadLocationInput = document.getElementById("downloadLocation");
const saveDownloadLocationButton = document.getElementById("saveDownloadLocation");
const downloadLocationStatus = document.getElementById("downloadLocationStatus");

const installerUrlInput = document.getElementById("downloadInstallerUrl");
const downloadInstallerButton = document.getElementById("downloadInstallerButton");
const installerUploadInput = document.getElementById("installerUpload");
const uploadInstallerButton = document.getElementById("uploadInstallerButton");
const installerIngestStatus = document.getElementById("installerIngestStatus");
const installerSelect = document.getElementById("installerSelect");

const analysisAppNameInput = document.getElementById("analysisAppName");
const researchUrlsInput = document.getElementById("researchUrls");
const allowRuntimeProbeInput = document.getElementById("allowRuntimeProbe");
const analyzeInstallerButton = document.getElementById("analyzeInstallerButton");
const analysisOutput = document.getElementById("analysisOutput");

const runPackageButton = document.getElementById("runPackageButton");
const packageOutput = document.getElementById("packageOutput");

const packageFields = {
  appName: document.getElementById("pkgAppName"),
  websiteUrl: document.getElementById("pkgWebsiteUrl"),
  downloadUrl: document.getElementById("pkgDownloadUrl"),
  version: document.getElementById("pkgVersion"),
  publisher: document.getElementById("pkgPublisher"),
  developerUrl: document.getElementById("pkgDeveloperUrl"),
  supportUrl: document.getElementById("pkgSupportUrl"),
  installCommand: document.getElementById("pkgInstallCommand"),
  iconPath: document.getElementById("pkgIconPath"),
};

function setStatus(target, message, isError = false) {
  target.textContent = message;
  target.classList.toggle("error", isError);
}

async function jsonRequest(url, method = "GET", body) {
  const response = await fetch(url, {
    method,
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || payload.result?.error || "Request failed.");
  }
  return payload;
}

function renderInstallerOptions(installers) {
  installerSelect.innerHTML = "";
  if (!installers.length) {
    const option = document.createElement("option");
    option.value = "";
    option.textContent = "No installers uploaded or downloaded yet";
    installerSelect.appendChild(option);
    return;
  }

  installers.forEach((installer) => {
    const option = document.createElement("option");
    option.value = installer.id;
    option.textContent = `${installer.originalName} (${installer.source})`;
    installerSelect.appendChild(option);
  });
}

async function refreshInstallers() {
  const payload = await jsonRequest("/api/installers");
  renderInstallerOptions(payload.installers || []);
}

async function loadDownloadLocation() {
  const payload = await jsonRequest("/api/config/download-location");
  downloadLocationInput.value = payload.downloadLocation || "";
}

saveDownloadLocationButton.addEventListener("click", async () => {
  try {
    const payload = await jsonRequest("/api/config/download-location", "PUT", {
      downloadLocation: downloadLocationInput.value,
    });
    setStatus(downloadLocationStatus, `Saved: ${payload.downloadLocation}`);
  } catch (error) {
    setStatus(downloadLocationStatus, error.message, true);
  }
});

downloadInstallerButton.addEventListener("click", async () => {
  setStatus(installerIngestStatus, "Downloading installer...");
  try {
    const payload = await jsonRequest("/api/installers/download", "POST", {
      url: installerUrlInput.value,
    });
    await refreshInstallers();
    let message = `Downloaded: ${payload.installer.originalName}`;
    if (payload.warning) {
      message += ` (${payload.warning})`;
    }
    setStatus(installerIngestStatus, message);
  } catch (error) {
    setStatus(installerIngestStatus, error.message, true);
  }
});

uploadInstallerButton.addEventListener("click", async () => {
  const file = installerUploadInput.files?.[0];
  if (!file) {
    setStatus(installerIngestStatus, "Select a file first.", true);
    return;
  }

  const formData = new FormData();
  formData.append("file", file);
  setStatus(installerIngestStatus, "Uploading installer...");

  try {
    const response = await fetch("/api/installers/upload", {
      method: "POST",
      body: formData,
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(payload.error || "Upload failed.");
    }
    await refreshInstallers();
    setStatus(installerIngestStatus, `Uploaded: ${payload.installer.originalName}`);
    installerUploadInput.value = "";
  } catch (error) {
    setStatus(installerIngestStatus, error.message, true);
  }
});

analyzeInstallerButton.addEventListener("click", async () => {
  const installerId = installerSelect.value;
  if (!installerId) {
    analysisOutput.textContent = "Select an installer before analysis.";
    return;
  }

  analysisOutput.textContent = "Analyzing installer...";
  const researchUrls = researchUrlsInput.value
    .split("\n")
    .map((value) => value.trim())
    .filter(Boolean);

  try {
    const payload = await jsonRequest("/api/installers/analyze", "POST", {
      installerId,
      appName: analysisAppNameInput.value,
      researchUrls,
      allowRuntimeProbe: allowRuntimeProbeInput.checked,
    });
    analysisOutput.textContent = JSON.stringify(payload.analysis, null, 2);
  } catch (error) {
    analysisOutput.textContent = error.message;
  }
});

runPackageButton.addEventListener("click", async () => {
  packageOutput.textContent = "Running packaging script...";
  const payload = {};
  Object.entries(packageFields).forEach(([key, input]) => {
    payload[key] = input.value;
  });

  try {
    const response = await jsonRequest("/api/packages/create", "POST", payload);
    packageOutput.textContent = JSON.stringify(response.result, null, 2);
  } catch (error) {
    packageOutput.textContent = error.message;
  }
});

async function bootstrap() {
  try {
    await loadDownloadLocation();
    await refreshInstallers();
  } catch (error) {
    setStatus(downloadLocationStatus, error.message, true);
  }
}

bootstrap();
