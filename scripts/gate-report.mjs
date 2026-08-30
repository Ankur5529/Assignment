#!/usr/bin/env node
// Reads gate output files from test-results/ and produces gate-report.json
//
// Usage: node scripts/gate-report.mjs <tier>
//
// Output schema:
// {
//   "tier": 0,
//   "commit": "a1b2c3d",
//   "status": "failed"|"passed",
//   "failureSignature": "sha256:...",  // hash of sorted (gate, file, rule) tuples
//   "gates": [
//     { "gate": "typecheck", "status": "failed", "failures": [
//       { "file": "src/hooks/useCart.ts", "line": 42, "code": "TS2345", "message": "..." }
//     ] },
//     { "gate": "lint", "status": "passed", "failures": [] }
//   ]
// }

import { createHash } from 'crypto'
import { existsSync, readFileSync, writeFileSync } from 'fs'
import { execSync } from 'child_process'

const tier = parseInt(process.argv[2] ?? '0', 10)



function getCurrentCommit() {
  try {
    return execSync('git rev-parse --short HEAD', { encoding: 'utf8' }).trim()
  } catch {
    return 'unknown'
  }
}

function readFile(path) {
  if (!existsSync(path)) return null
  return readFileSync(path, 'utf8')
}

function computeSignature(failures) {
  // failureSignature = SHA-256 of sorted (gate, file, rule) tuples
  const tuples = failures
    .flatMap((gateResult) =>
      gateResult.failures.map((f) => `${gateResult.gate}:${f.file}:${f.code}`)
    )
    .sort()
  const data = tuples.join('\n')
  return 'sha256:' + createHash('sha256').update(data).digest('hex')
}


// tsc format: src/hooks/useCart.ts(42,5): error TS2345: Argument...
function parseTscOutput(raw) {
  if (!raw) return []
  const failures = []
  const re = /^(.+?)\((\d+),\d+\):\s+error\s+(TS\d+):\s+(.+)$/gm
  let m
  while ((m = re.exec(raw)) !== null) {
    failures.push({
      file: m[1].replace(/\\/g, '/'),
      line: parseInt(m[2], 10),
      code: m[3],
      message: m[4].trim(),
    })
  }
  return failures
}


function parseBiomeJson(raw) {
  if (!raw) return []
  try {
    const report = JSON.parse(raw)
    const failures = []
    const diagnostics = report.diagnostics ?? []
    for (const d of diagnostics) {
      if (d.severity !== 'error') continue
      const loc = d.location ?? {}
      const span = loc.span ?? {}
      failures.push({
        file: (loc.path?.file ?? 'unknown').replace(/\\/g, '/'),
        line: span.start?.line ?? 0,
        code: d.category ?? 'lint/unknown',
        message: d.description ?? '',
      })
    }
    return failures
  } catch {
    return []
  }
}


function parsePlywrightJson(raw) {
  if (!raw) return []
  try {
    const report = JSON.parse(raw)
    const failures = []
    function walkSuite(suite) {
      for (const spec of suite.specs ?? []) {
        for (const test of spec.tests ?? []) {
          if (test.status !== 'unexpected') continue
          const result = test.results?.[0] ?? {}
          failures.push({
            file: spec.file?.replace(/\\/g, '/') ?? 'unknown',
            line: spec.line ?? 0,
            code: 'e2e/test-failure',
            message: `[${spec.title}] ${result.error?.message ?? result.status ?? 'failed'}`,
          })
        }
      }
      for (const child of suite.suites ?? []) {
        walkSuite(child)
      }
    }
    walkSuite(report)
    return failures
  } catch {
    return []
  }
}


const commit = getCurrentCommit()

const standardsStatus = existsSync('test-results/standards-failed') ? 'failed' : 'passed'

const biomeRaw = readFile('test-results/biome-report.json')
const biomeFailures = parseBiomeJson(biomeRaw)
const lintStatus = biomeFailures.length > 0 ? 'failed' : 'passed'

const tscRaw = readFile('test-results/tsc-output.txt')
const tscFailures = parseTscOutput(tscRaw)
const typecheckStatus = tscFailures.length > 0 ? 'failed' : 'passed'

const buildOutputRaw = readFile('test-results/build-output.txt')
const buildFailed = buildOutputRaw?.includes('error') ?? false
const buildStatus = buildFailed ? 'failed' : 'passed'

const gates = [
  { gate: 'standards', status: standardsStatus, failures: [] },
  { gate: 'lint', status: lintStatus, failures: biomeFailures },
  { gate: 'typecheck', status: typecheckStatus, failures: tscFailures },
  { gate: 'build', status: buildStatus, failures: [] },
]

if (tier >= 1) {
  const pwRaw = readFile('test-results/playwright-report.json')
  const pwFailures = parsePlywrightJson(pwRaw)
  const e2eStatus = pwFailures.length > 0 ? 'failed' : 'passed'
  gates.push({ gate: 'e2e', status: e2eStatus, failures: pwFailures })
}

const anyFailed = gates.some((g) => g.status === 'failed')
const overallStatus = anyFailed ? 'failed' : 'passed'
const failureSignature = computeSignature(gates.filter((g) => g.status === 'failed'))

const report = {
  tier,
  commit,
  status: overallStatus,
  failureSignature,
  gates,
}

const outPath = 'test-results/gate-report.json'
writeFileSync(outPath, JSON.stringify(report, null, 2))
console.log(`[gate-report] Written to ${outPath}`)
console.log(`[gate-report] Status: ${overallStatus} | Signature: ${failureSignature}`)

process.exit(anyFailed ? 1 : 0)
