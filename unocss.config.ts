import { defineConfig, escapeSelector } from "unocss";
import fs from "fs";

// npx unocss "options/options.html" "src/options_page.nim" -o dist/main.css

// TODO: check out unocss presets

const config = defineConfig({
  rules: [
    [/^basis\-(\d+)(\w*)$/, ruleFlexBasis],
    [/^stack\-?(\d*)(\w*)$/, ruleStack, {layer: "component"}],
    [/^l-grid-?(\d*)(\w*)$/, ruleLayoutGrid, {layer: "component"}],
    [/^switcher-?(\d*)(\w*)$/, ruleSwitcher, {layer: "component"}],
    [/^tooltip$/, ruleTooltip, {layer: "component"}],
  ],
  shortcutsLayer: "component",
  shortcuts: [
    ["btn", "px-3 py-2 rounded-sm"],
    ["btn-small", "px-2 py-1 rounded-sm"],
    ["btn-pocket", "text-sky-500 border-2 border-sky-400 hover:bg-sky-400 hover:text-white"],

    ["rule-btn-add", "w-full py-0.5 px-2 border-3 border-dashed text-center border-blue-100 text-blue-400 font-bold hover:border-blue-400 focus:border-blue-400"],
    ["rule-label", "bg-blue-100 inline-block px-1"],
    ["rule-input-wrapper", "p-1 bg-blue-100 flex-1"],
    ["rule-input", "border-2 border-transparent hover:border-blue-400 focus:border-blue-400 w-full px-1"],
    ["rule-btn-remove-wrapper", "bg-red-50 rounded-r-full p-1 text-red-900"],
    ["rule-btn-remove", "bg-white block h-full rounded-full px-1.5 hover:bg-red-200"],
    ["rule-btn-toggle", "bg-white rounded-full w-6 h-6 flex place-items-center justify-center hover:bg-gray-300"],
    ["rule-title", "bg-gray-100 w-full px-3 py-1 text-4.25 flex justify-between"],
    ["rule-container", "bg-truegray-50 block p-3"],
  ],
  preflights: [
    { getCSS: () => fs.readFileSync("node_modules/@unocss/reset/tailwind.css").toString(), layer: "reset" },
    { getCSS: () => fs.readFileSync("src/styles/main.css").toString(), layer: "base" },
    { getCSS: () => `
      .rule-btn-toggle[aria-expanded='true']{
        transform: rotate(0.5turn)
      }
    `, layer: "component" },
  ],
  layers: {
    reset: 0,
    base: 1,
    component: 2,
    default: 3,
  },
});

function ruleStack([selector, nr, unit]) {
  const css_attr = "--space"

  if (nr === '' && unit === '') {
    const classSelector = "." + escapeSelector(selector)
    return `
${classSelector} {
  display: flex;
  flex-direction: column;
  justify-content: flex-start;
  ${css_attr}: 1.5rem;
}
${classSelector} > template + *,
${classSelector} > * {
  margin-top: 0;
  margin-bottom: 0;
}

${classSelector} > * + * { margin-top: var(${css_attr}); }
    `
  }

  if (unit !== '') return { [css_attr]: `${nr}${unit}` }
  if (nr !== '') return { [css_attr]: `${nr / 4}rem` }

  return `/* Error: Failed to generate stack rule from ${selector} */`
}

function ruleFlexBasis([selector, nr, unit]) {
  if (unit !== '') return { "flex-basis": `${nr}${unit}` }
  if (nr !== '') return { "flex-basis": `${nr / 4}rem` }

  return `/* Error: Failed to generate flex-basis rule from ${selector} */`
}

async function ruleLayoutGrid([selector, nr, unit]) {
  const css_attr = "--grid-min"
  if (nr === '') {
    const classSelector = "." + escapeSelector(selector)
    return `
${classSelector} {
  display: grid;
  grid-gap: 1rem;
  grid-template-columns: 100%;
  ${css_attr}: 20ch;
}
@supports (width: min(var(${css_attr}), 100%)) {
  ${classSelector} { grid-template-columns: repeat(auto-fill, minmax(min(var(${css_attr}), 100%), 1fr)); }
}
    `
  }

  if (unit !== '') return { [css_attr]: `${nr}${unit}` }
  if (nr !== '') return { [css_attr]: `${nr / 4}rem` }

  return `/* Error: Failed to generate l-grid rule from ${selector} */`
}

function ruleSwitcher([selector, nr, unit]) {
  const css_attr = "--threshold"

  if (nr === '' && unit === '') {
    const classSelector = "." + escapeSelector(selector)
    return `
${classSelector} {
  display: flex;
  flex-wrap: wrap;
  ${css_attr}: 30rem;
}
${classSelector} > * {
  flex-grow: 1;
  flex-basis: calc((var(${css_attr}) - 100%) * 999)
}
    `
  }

  if (unit !== '') return { [css_attr]: `${nr}${unit}` }
  if (nr !== '') return { [css_attr]: `${nr / 4}rem` }

  return `/* Error: Failed to generate switcher rule from ${selector} */`
}

function ruleTooltip() {
  return `
.btn-tooltip:hover + .tooltip,
.btn-tooltip:focus + .tooltip {
  display: block;
}

.tooltip {
  display: none;
  font-size: 0.875rem;
  background: #EFF6FF;
  padding: 0.5rem;
  position: absolute;
  bottom: 100%;
  right: 0;
  margin-bottom: 12px;
  border-bottom: 3px solid #DBEAFE;
}

.tooltip:before {
  content: "";
  position: absolute;
  top: 100%;
  right: 0;
  margin-top: 3px;
  border-left: 15px solid transparent;
  border-right: 15px solid transparent;
  border-top: 10px solid #DBEAFE;
}
  `
}


export default config
