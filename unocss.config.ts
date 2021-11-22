import { defineConfig, escapeSelector } from "unocss";
import fs from "fs";

// npx unocss "options/options.html" "src/options_page.nim" -o dist/main.css

const config = defineConfig({
  rules: [
    [/^stack\-?(\d*)(\w*)$/, ruleStack],
  ],
  shortcutsLayer: "component",
  shortcuts: [
    ["btn", "px-3 py-2 rounded-sm"],
    ["btn-pocket", "text-sky-500 border-2 border-sky-400 hover:bg-sky-400 hover:text-white"],
    ["textbox", "max-w-50ch w-30ch min-h-8em border-2 rounded-sm border-truegray-300"],
    ["fieldset-wrapper", "bg-indigo-50 p-4"],
    ["input-wrapper", "bg-indigo-100 p-2 w-max"],
    ["legend-title", "text-lg border-b-4 border-indigo-100 text-indigo-900"],
  ],
  preflights: [
    { getCSS: () => fs.readFileSync("node_modules/@unocss/reset/tailwind.css").toString(), layer: "reset" },
    { getCSS: () => fs.readFileSync("src/styles/main.css").toString(), layer: "base" },
  ],
  layers: {
    reset: 0,
    base: 1,
    component: 2,
    default: 3,
  },
});

function ruleStack([selector, nr, unit]) {
  console.log("stack")
  const classSelector = "." + escapeSelector(selector)
  const css_attr = "--space"

  if (nr === '' && unit === '') {
    return `
${classSelector} { display: flex; flex-direction: column; justify-content: flex-start; }
${classSelector} > template + *,
${classSelector} > * {
  margin-top: 0;
  margin-bottom: 0;
}

${classSelector} > * + * { margin-top: var(${css_attr}, 1.5rem); }
    `
  }

  if (unit !== '') return `${classSelector} { ${css_attr}: ${nr}${unit}; }`
  if (nr !== '') return `${classSelector} { ${css_attr}: ${nr / 4}rem; }`

  return `/* Failed to generate stack rule from ${selector} */`
}

export default config
