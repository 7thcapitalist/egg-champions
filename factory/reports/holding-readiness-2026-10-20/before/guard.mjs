#!/usr/bin/env node
// Guarda de orçamento por estúdio.
//   node scripts/guard.mjs check <studio>             -> imprime OK | STOP | UNKNOWN + motivo (exit 0 / 3 / 0)
//   node scripts/guard.mjs record <studio> start|end <runId>  -> grava snapshot de quota no ledger
// O consumo de um estúdio na semana = soma de (end - start) do % semanal, por run, desde o último reset.
// Runs simultâneos de estúdios diferentes contaminam a diferença; o manager despacha IA pesada um estúdio por vez.
import { readFileSync, appendFileSync, existsSync, mkdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { codexQuota, claudeQuota } from './quota.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const budget = JSON.parse(readFileSync(join(ROOT, 'budget.json'), 'utf8'))
const LEDGER = join(ROOT, 'ledger', 'quota.jsonl')
const STALE_MIN = 6 * 60

const [cmd, studio, phase, runId] = process.argv.slice(2)
if (!['check', 'record'].includes(cmd) || !budget.studios[studio]) {
  console.error('uso: guard.mjs check <software|roblox|website> | record <studio> start|end <runId>')
  process.exit(2)
}
const q = { codex: codexQuota(), claude: claudeQuota() }

if (cmd === 'record') {
  if (!['start', 'end'].includes(phase) || !runId) { console.error('record precisa de start|end e runId'); process.exit(2) }
  mkdirSync(dirname(LEDGER), { recursive: true })
  appendFileSync(LEDGER, JSON.stringify({
    at: new Date().toISOString(), studio, phase, runId,
    codex_pct: q.codex?.used_pct ?? null, codex_resets_at: q.codex?.resets_at ?? null,
    claude_pct: q.claude?.used_pct ?? null, claude_resets_at: q.claude?.resets_at ?? null,
  }) + '\n')
  console.log('recorded')
  process.exit(0)
}

// ---- check ----
const reasons = []
let verdict = 'OK'
const r = budget.reserve_for_joao
for (const [k, max] of [['codex', r.codex_weekly_max_pct], ['claude', r.claude_weekly_max_pct]]) {
  const m = q[k]
  if (!m) { reasons.push(`${k}: sem medição`); if (verdict === 'OK') verdict = 'UNKNOWN'; continue }
  if (m.age_min > STALE_MIN) { reasons.push(`${k}: medição velha (${m.age_min} min)`); if (verdict === 'OK') verdict = 'UNKNOWN' }
  if (m.used_pct >= max) { reasons.push(`${k}: ${m.used_pct}% usado ≥ reserva do João (${max}%)`); verdict = 'STOP' }
  if (k === 'codex' && m.paid_credits) { reasons.push('codex: créditos pagos ativos — policy §1 proíbe gastar'); verdict = 'STOP' }
}

function weeklyShareUsed(key) {
  if (!existsSync(LEDGER)) return 0
  const resets = q[key]?.resets_at ? Date.parse(q[key].resets_at) : null
  const weekStart = resets ? resets - 7 * 24 * 3600 * 1000 : Date.now() - 7 * 24 * 3600 * 1000
  const rows = readFileSync(LEDGER, 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l))
    .filter((x) => x.studio === studio && Date.parse(x.at) >= weekStart)
  const starts = new Map(rows.filter((x) => x.phase === 'start').map((x) => [x.runId, x]))
  let sum = 0
  for (const e of rows.filter((x) => x.phase === 'end')) {
    const s = starts.get(e.runId)
    const a = s?.[`${key}_pct`], b = e[`${key}_pct`]
    if (typeof a === 'number' && typeof b === 'number' && b >= a) sum += b - a
  }
  return Math.round(sum * 10) / 10
}

const s = budget.studios[studio]
const shares = {
  roblox: [['codex', s.codex_weekly_share_pct], ['claude', s.claude_weekly_share_pct]],
  website: [['codex', s.improvement_codex_weekly_share_pct], ['claude', s.improvement_claude_weekly_share_pct]],
  software: [],
}[studio]
const usage = {}
for (const [k, cap] of shares) {
  if (cap == null) continue
  const used = weeklyShareUsed(k)
  usage[k] = { used_pct_of_plan: used, cap_pct_of_plan: cap }
  if (used >= cap) { reasons.push(`${studio}: já usou ${used}% do ${k} nesta semana (teto ${cap}%)`); verdict = 'STOP' }
}
if (studio === 'website') reasons.push('builds de clientes seguem a demanda; o teto acima vale para trabalho de melhoria')

console.log(JSON.stringify({ verdict, studio, reasons, usage, quota: q }, null, 2))
process.exit(verdict === 'STOP' ? 3 : 0)
