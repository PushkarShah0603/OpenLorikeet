"use strict";

const demo = document.querySelector("#demo");
const title = document.querySelector("#demo-title");
const status = document.querySelector("#demo-status");
const buttons = [...demo.querySelectorAll("[data-format]")];
const reset = document.querySelector("#reset-demo");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let completion;

function clearDemo() {
  window.clearTimeout(completion);
  demo.classList.remove("is-done");
  for (const button of buttons) button.setAttribute("aria-pressed", "false");
}

for (const button of buttons) {
  button.setAttribute("aria-pressed", "false");
  button.addEventListener("click", () => {
    clearDemo();
    button.setAttribute("aria-pressed", "true");
    const format = button.dataset.format;
    const compressed = button.dataset.action === "Compress";
    title.textContent = compressed ? "Compressing PNG" : "Converting to " + format;
    status.textContent = "Preview conversion in progress";
    completion = window.setTimeout(() => {
      title.textContent = "Preview complete";
      status.textContent = compressed ? "postcard (compressed).png" : "postcard." + format.toLowerCase();
      demo.classList.add("is-done");
    }, reducedMotion.matches ? 0 : 420);
  });
}

reset.addEventListener("click", () => {
  clearDemo();
  title.textContent = "Choose an output";
  status.textContent = "Example file · postcard.png";
});
