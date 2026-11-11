"use strict";
const platforms = {
  mac: { title: "macOS 15+ · Apple silicon", copy: "Native menu bar app. Shift-drag in Finder; Command-drag for PDF tools. Built locally on Apple silicon.", command: "1. Download and open the ZIP.\n2. Drag OpenLorikeet.app into Applications.\n3. Open it from Applications.", link: "https://github.com/PushkarShah0603/OpenLorikeet/releases", label: "Check releases ↗" },
  windows: { title: "Windows 10 / 11 · x64", copy: "Tray app. Shift-drag a file or use Convert files from the tray. Install LibreOffice for Word-to-PDF. Development build; desktop acceptance testing is pending.", command: "1. Download the Windows setup file.\n2. Open it and follow the setup wizard.\n3. Launch OpenLorikeet from the Start menu.", link: "https://github.com/PushkarShah0603/OpenLorikeet/releases", label: "View releases ↗" },
  linux: { title: "Linux · x64", copy: "Installable tray app for Debian/Ubuntu x64. Shift-drag on X11; open the drop wheel from the tray on Wayland. GNOME may need a tray extension. Development build; desktop acceptance testing is pending.", command: "1. Download the Debian/Ubuntu installer.\n2. Open it with your Software Installer.\n3. Launch OpenLorikeet from the app menu.", link: "https://github.com/PushkarShah0603/OpenLorikeet/releases", label: "View releases ↗" }
};

const releasePage = "https://github.com/PushkarShah0603/OpenLorikeet/releases";
let selectedPlatform = "mac";
let downloadAssets = {};
let downloadStatus = "Checking published packages…";

function renderPlatform() {
  const platform = platforms[selectedPlatform];
  for (const button of document.querySelectorAll("[data-platform]")) button.setAttribute("aria-pressed", String(button.dataset.platform === selectedPlatform));
  document.querySelector("#platform-title").textContent = platform.title;
  document.querySelector("#platform-copy").textContent = platform.copy;
  const assetForInstructions = downloadAssets[selectedPlatform];
  const portable = assetForInstructions && (assetForInstructions.name.endsWith('.tar.gz') || selectedPlatform === 'windows' && assetForInstructions.name.endsWith('.zip'));
  document.querySelector("#platform-command").textContent = portable
    ? "1. Download and extract the entire archive.\n2. Keep the extracted folder together.\n3. Open OpenLorikeet inside that folder."
    : platform.command;
  const asset = downloadAssets[selectedPlatform];
  const link = document.querySelector("#platform-link");
  link.href = asset ? asset.browser_download_url : releasePage;
  link.textContent = asset ? "Download " + asset.name : "View releases ↗";
  const availability = document.querySelector("#platform-availability");
  if (availability) availability.textContent = asset ? "Development package · " + Math.ceil(asset.size / 1048576) + " MB · " + (asset.name.endsWith("-Setup.exe") ? "run the setup wizard" : asset.name.endsWith(".deb") ? "install on Debian/Ubuntu" : "extract before opening") : downloadStatus;
}
for (const button of document.querySelectorAll("[data-platform]")) {
  button.addEventListener("click", () => { selectedPlatform = button.dataset.platform; renderPlatform(); });
}

async function loadDownloads() {
  try {
    const response = await fetch("https://api.github.com/repos/PushkarShah0603/OpenLorikeet/releases?per_page=20", { signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error("Release lookup failed");
    const releases = await response.json();
    if (!Array.isArray(releases)) throw new Error("Invalid release response");
    for (const release of releases) {
      if (release.draft) continue;
      const assets = (release.assets || []).filter(asset => asset.state === "uploaded" && asset.size > 0 && typeof asset.browser_download_url === "string" && asset.browser_download_url.startsWith(releasePage + "/download/"));
      const candidate = {
        windows: assets.find(asset => asset.name === "OpenLorikeet-Windows-x64-Setup.exe") || assets.find(asset => asset.name === "OpenLorikeet-Windows-x64.zip"),
        linux: assets.find(asset => asset.name === "OpenLorikeet-Linux-x64.deb") || assets.find(asset => asset.name === "OpenLorikeet-Linux-x64.tar.gz"),
        mac: assets.find(asset => asset.name === "OpenLorikeet-macOS-arm64.zip")
      };
      // Publish a coherent download set; ignore incomplete/draft releases.
      if (candidate.windows && candidate.linux && candidate.mac) { downloadAssets = candidate; break; }
    }
    downloadStatus = "Packages have not been published yet. Build instructions are below.";
  } catch (_) {
    downloadStatus = "Cannot check packages right now. Open releases to see available downloads.";
  }
  renderPlatform();
}
renderPlatform();
if (typeof fetch === "function") loadDownloads();
