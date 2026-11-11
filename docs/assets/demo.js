"use strict";

const demo = document.querySelector("#demo");
const title = document.querySelector("#demo-title");
const status = document.querySelector("#demo-status");
const buttons = [...demo.querySelectorAll("[data-format]")];
const reset = document.querySelector("#reset-demo");
const play = document.querySelector("#play-demo");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let completion;

function clearDemo() {
  window.clearTimeout(completion);
  demo.classList.remove("is-done", "is-playing");
  play.disabled = false;
  for (const button of buttons) button.setAttribute("aria-pressed", "false");
}

function choose(button) {
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
}

for (const button of buttons) {
  button.setAttribute("aria-pressed", "false");
  button.addEventListener("click", () => choose(button));
}

play.addEventListener("click", () => {
  clearDemo();
  play.disabled = true;
  title.textContent = "Shift-drag to PDF";
  status.textContent = "Moving postcard.png onto the PDF segment";
  demo.classList.add("is-playing");
  const pdf = buttons.find(button => button.dataset.format === "PDF");
  completion = window.setTimeout(() => choose(pdf), reducedMotion.matches ? 0 : 950);
});

reset.addEventListener("click", () => {
  clearDemo();
  title.textContent = "Choose an output";
  status.textContent = "Example file · postcard.png";
});
