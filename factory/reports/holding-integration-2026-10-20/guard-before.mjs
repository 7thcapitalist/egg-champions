#!/usr/bin/env node
// Guarda de orçamento por estúdio.
//   node scripts/guard.mjs check <studio>             -> imprime OK | STOP | UNKNOWN + motivo (exit 0 / 3 / 3)
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
const MAX_AGE_MS = 300_000

const [cmd, studio, phase, runId] = process.argv.slice(2)
const providers = cmd === 'check' && phase ? [phase] : ['codex', 'claude']
if (!['check', 'record'].includes(cmd) || !budget.studios[studio]) {
  console.error('uso: guard.mjs check <software|roblox|website> | record <studio> start|end <runId>')
  process.exit(2)
}
if (providers.some((provider) => !['codex', 'claude'].includes(provider))) process.exit(2)
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
  if (!providers.includes(k)) continue
  const m = q[k]
  if (!m) { reasons.push(`${k}: sem medição`); if (verdict === 'OK') verdict = 'UNKNOWN'; continue }
  const age = Date.now() - Date.parse(m.measured_at)
  if (!Number.isFinite(age) || age < 0 || age > MAX_AGE_MS || typeof m.used_pct !== 'number' || !Number.isFinite(m.used_pct) || m.used_pct < 0 || m.used_pct > 100 || !m.source || !Number.isFinite(Date.parse(m.resets_at)) || Date.parse(m.resets_at) <= Date.now()) {
    reasons.push(`${k}: medicao ausente, invalida ou antiga`); if (verdict === 'OK') verdict = 'UNKNOWN'
  }
  if (!Number.isFinite(max) || max <= 0 || max > 100) { reasons.push(`${k}: reserva invalida`); verdict = 'STOP' }
  if (k === 'codex' && m.paid_credits !== false) { reasons.push('codex: estado de creditos desconhecido ou ativo'); verdict = 'STOP' }
  if (m.used_pct >= max) { reasons.push(`${k}: ${m.used_pct}% usado ≥ reserva do João (${max}%)`); verdict = 'STOP' }
  if (typeof m.five_hour_pct === 'number' && m.five_hour_pct >= 100) { reasons.push(`${k}: janela de cinco horas esgotada`); verdict = 'STOP' }
  if (k === 'codex' && m.paid_credits) { reasons.push('codex: créditos pagos ativos — policy §1 proíbe gastar'); verdict = 'STOP' }
}

function weeklyShareUsed(key) {
  // Missing/incomplete accounting is unknown, never zero consumption.
  if (!existsSync(LEDGER)) throw new Error('ledger semanal ausente')
  const resets = Date.parse(q[key]?.resets_at)
  if (!Number.isFinite(resets)) throw new Error('reset semanal desconhecido')
  const weekStart = resets - 7 * 24 * 3600 * 1000
  const raw = readFileSync(LEDGER, 'utf8').trim()
  if (!raw) throw new Error('ledger semanal vazio sem baseline autorizado')
  const rows = raw.split('\n').filter(Boolean).map((line) => JSON.parse(line))
  const starts = new Map(), ends = new Set()
  let sum = 0
  for (const row of rows) {
    const at = Date.parse(row.at)
    if (!Number.isFinite(at) || at > Date.now() || typeof row.runId !== 'string' || !row.runId || !budget.studios[row.studio] || !['start', 'end'].includes(row.phase)) throw new Error('linha invalida no ledger')
    const id = row.studio + ':' + row.runId
    if (row.phase === 'start') {
      if (starts.has(id) || ends.has(id)) throw new Error('run duplicado no ledger')
      starts.set(id, row)
    } else {
      const start = starts.get(id)
      if (!start || ends.has(id) || Date.parse(start.at) > at) throw new Error('fim sem inicio unico e ordenado')
      ends.add(id)
      if (row.studio !== studio || at < weekStart) continue
      const a = start[`${key}_pct`], b = row[`${key}_pct`]
      if (Date.parse(start.at) < weekStart || start[`${key}_resets_at`] !== q[key].resets_at || row[`${key}_resets_at`] !== q[key].resets_at) throw new Error('run cruza reset ou pertence a outra janela')
      if ([a,b].some((n) => typeof n !== 'number' || !Number.isFinite(n) || n < 0 || n > 100) || b < a) throw new Error('consumo desconhecido ou regressivo')
      sum += b - a
    }
  }
  if ([...starts].some(([id]) => !ends.has(id))) throw new Error('run sem medicao final: nao admitir outro')
  // Do not round down close to the authorized share.
  return sum
}

const s = budget.studios[studio]
const shares = {
  roblox: [['codex', s.codex_weekly_share_pct], ['claude', s.claude_weekly_share_pct]],
  website: [['codex', s.improvement_codex_weekly_share_pct], ['claude', s.improvement_claude_weekly_share_pct]],
  software: [],
}[studio]
const usage = {}
for (const [k, cap] of shares) {
  if (!providers.includes(k)) continue
  let used
  try {
    if (typeof cap !== 'number' || !Number.isFinite(cap) || cap <= 0 || cap > 100) throw new Error('teto invalido')
    used = weeklyShareUsed(k)
  } catch (error) {
    reasons.push(`${k}: ${error.message}`)
    usage[k] = { used_pct_of_plan: null, cap_pct_of_plan: cap }
    if (verdict === 'OK') verdict = 'UNKNOWN'
    continue
  }
  usage[k] = { used_pct_of_plan: used, cap_pct_of_plan: cap }
  if (used >= cap) { reasons.push(`${studio}: já usou ${used}% do ${k} nesta semana (teto ${cap}%)`); verdict = 'STOP' }
}
if (studio === 'website') reasons.push('builds de clientes seguem a demanda; o teto acima vale para trabalho de melhoria')

console.log(JSON.stringify({ verdict, studio, provider_scope: providers, reasons, usage, quota: q }, null, 2))
process.exit(verdict === 'OK' ? 0 : 3)
