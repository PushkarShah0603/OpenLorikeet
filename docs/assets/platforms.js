"use strict";
const platforms = {
  mac: { title: "macOS 15+", copy: "Native menu bar app. Shift-drag in Finder; Command-drag for PDF tools. Built locally on Apple silicon.", command: "./scripts/package.sh\nopen dist/OpenLorikeet.app", link: "https://github.com/PushkarShah0603/OpenLorikeet/releases", label: "Check releases ↗" },
  windows: { title: "Windows 10 / 11 · x64", copy: "Portable tray app. Shift-drag a file or use Convert files from the tray. Install LibreOffice for Word-to-PDF. Development build; desktop acceptance testing is pending.", command: "py -3.12 -m pip install -r desktop/requirements.txt\npy -3.12 desktop/build.py", link: "https://github.com/PushkarShah0603/OpenLorikeet/releases", label: "View releases ↗" },
  linux: { title: "Linux · x64", copy: "Portable tray app for desktop Linux. Shift-drag on X11; open the drop wheel from the tray on Wayland. GNOME may need a tray extension. Development build; desktop acceptance testing is pending.", command: "python3 -m venv .venv\n. .venv/bin/activate\npip install -r desktop/requirements.txt\npython desktop/build.py", link: "https://github.com/PushkarShah0603/OpenLorikeet/releases", label: "View releases ↗" }
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
  document.querySelector("#platform-command").textContent = platform.command;
  const asset = downloadAssets[selectedPlatform];
  const link = document.querySelector("#platform-link");
  link.href = asset ? asset.browser_download_url : releasePage;
  link.textContent = asset ? "Download " + asset.name : "View releases ↗";
  const availability = document.querySelector("#platform-availability");
  if (availability) availability.textContent = asset ? "Development package · " + Math.ceil(asset.size / 1048576) + " MB · extract before opening" : downloadStatus;
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
        windows: assets.find(asset => asset.name === "OpenLorikeet-Windows-x64.zip"),
        linux: assets.find(asset => asset.name === "OpenLorikeet-Linux-x64.tar.gz"),
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
if (typeof fetch === "function") loadDownloads();
