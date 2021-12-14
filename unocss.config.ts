import { defineConfig, escapeSelector } from "unocss";
import fs from "fs";

// npx unocss "options/options.html" "src/options_page.nim" -o dist/main.css

const config = defineConfig({
  rules: [
    [/^stack\-?(\d*)(\w*)$/, ruleStack],
    [/^basis\-(\d+)(\w*)$/, ruleFlexBasis],
    [/^l-grid-?(.*)$/, ruleLayoutGrid, {layer: "component"}],
  ],
  shortcutsLayer: "component",
  shortcuts: [
    ["btn", "px-3 py-2 rounded-sm"],
    ["btn-small", "px-2 py-1 rounded-sm"],
    ["btn-add-rule", "py-1 px-2 border-4 border-dashed font-bold"],
    ["btn-pocket", "text-sky-500 border-2 border-sky-400 hover:bg-sky-400 hover:text-white"],
    ["textbox", "max-w-50ch w-30ch min-h-8em border-2 rounded-sm border-truegray-300"],
    ["fieldset-wrapper", "bg-indigo-50 p-4 flex-1 basis-10"],
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
  const css_attr = "--space"

  if (nr === '' && unit === '') {
    const classSelector = "." + escapeSelector(selector)
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

  if (unit !== '') return { [css_attr]: `${nr}${unit}` }
  if (nr !== '') return { [css_attr]: `${nr / 4}rem` }

  return `/* Error: Failed to generate stack rule from ${selector} */`
}

function ruleFlexBasis([selector, nr, unit]) {
  if (unit !== '') return { "flex-basis": `${nr}${unit}` }
  if (nr !== '') return { "flex-basis": `${nr / 4}rem` }

  return `/* Error: Failed to generate flex-basis rule from ${selector} */`
}

async function ruleLayoutGrid([selector, min_width], {generator}) {
  if (min_width === '') {
    const classSelector = "." + escapeSelector(selector)
    return `
${classSelector} {
  display: grid;
  grid-gap: 1rem;
  grid-template-columns: 100%;
}
@supports (width: min(var(--grid-min), 100%)) {
  ${classSelector} { grid-template-columns: repeat(auto-fill, minmax(min(var(--grid-min), 100%), 1fr)); }
}
    `
  }

  const [,,attrs] = await generator.parseUtil(min_width)
  const value = attrs[0][1]
  if (value) return { "--grid-min": value }

  return `/* Error: Failed to generate l-grid rule from ${selector} */`
}

export default config
