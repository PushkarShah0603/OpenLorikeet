"use strict";
const platforms = {
  mac: { title: "macOS 15+", copy: "Native menu bar app. Shift-drag in Finder; Command-drag for PDF tools. Built locally on Apple silicon.", command: "./scripts/package.sh\nopen dist/OpenLorikeet.app", link: "https://github.com/PushkarShah0603/OpenLorikeet/releases", label: "Check releases ↗" },
  windows: { title: "Windows 10 / 11 · x64", copy: "Portable tray app. Shift-drag a file or use Convert files from the tray. Install LibreOffice for Word-to-PDF. Native build verification is pending.", command: "py -3.12 -m pip install -r desktop/requirements.txt\npy -3.12 desktop/build.py", link: "https://github.com/PushkarShah0603/OpenLorikeet/actions/workflows/desktop.yml", label: "View build artifacts ↗" },
  linux: { title: "Linux · x64", copy: "Portable tray app for desktop Linux. Shift-drag on X11; open the drop wheel from the tray on Wayland. GNOME may need a tray extension. Native build verification is pending.", command: "python3 -m venv .venv\n. .venv/bin/activate\npip install -r desktop/requirements.txt\npython desktop/build.py", link: "https://github.com/PushkarShah0603/OpenLorikeet/actions/workflows/desktop.yml", label: "View build artifacts ↗" }
};
for (const button of document.querySelectorAll("[data-platform]")) {
  button.addEventListener("click", () => {
    const platform = platforms[button.dataset.platform];
    for (const item of document.querySelectorAll("[data-platform]")) item.setAttribute("aria-pressed", String(item === button));
    document.querySelector("#platform-title").textContent = platform.title;
    document.querySelector("#platform-copy").textContent = platform.copy;
    document.querySelector("#platform-command").textContent = platform.command;
    const link = document.querySelector("#platform-link"); link.href = platform.link; link.textContent = platform.label;
  });
}
