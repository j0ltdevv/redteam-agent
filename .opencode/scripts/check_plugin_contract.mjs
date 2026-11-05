// Mimics the OpenCode v2 PluginModule.load schema check, so plugin entry points
// can be validated without booting a server.
//
// Runtime contract (extracted from the opencode binary, v2.0.16):
//   default: z.union([
//     z.object({ id: z.string(), effect: z.function() }),
//     z.object({ id: z.string(), setup:  z.function() }),
//   ])
//
// Usage: bun .opencode/scripts/check_plugin_contract.mjs <path> [<path> ...]
import { pathToFileURL } from "node:url"
import { resolve } from "node:path"

const targets = process.argv.slice(2)

if (targets.length === 0) {
  console.error("usage: bun check_plugin_contract.mjs <path> [<path> ...]")
  process.exit(2)
}

let failed = 0

for (const raw of targets) {
  // Resolve against the current working directory, not this script's directory,
  // so relative targets behave the way they do when passed to `bun <script> <path>`.
  const target = pathToFileURL(resolve(process.cwd(), raw)).href
  const label = raw
  try {
    const mod = await import(target)
    const def = mod.default

    if (def === undefined) {
      console.log(`KO   ${label} — no default export`)
      failed++
      continue
    }
    if (typeof def !== "object" || def === null) {
      console.log(`KO   ${label} — default export is ${typeof def}, expected a definition object`)
      failed++
      continue
    }
    if (typeof def.id !== "string" || def.id.length === 0) {
      console.log(`KO   ${label} — default.id missing or not a string`)
      failed++
      continue
    }
    const hasEffect = typeof def.effect === "function"
    const hasSetup = typeof def.setup === "function"
    if (!hasEffect && !hasSetup) {
      console.log(`KO   ${label} — default has an id ("${def.id}") but no effect/setup function`)
      failed++
      continue
    }
    const kind = hasEffect ? "effect" : "setup"
    console.log(`OK   ${label} — id="${def.id}" ${kind}=function`)
  } catch (err) {
    console.log(`KO   ${label} — import failed: ${err.message}`)
    failed++
  }
}

console.log(`\n${targets.length - failed} ok / ${failed} failed`)
process.exit(failed === 0 ? 0 : 1)
