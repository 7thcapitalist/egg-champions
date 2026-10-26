#!/usr/bin/env node
// Guarda de orçamento por estúdio.
//   node scripts/guard.mjs check <studio>             -> imprime OK | STOP | UNKNOWN + motivo (exit 0 / 3 / 3)
//   node scripts/guard.mjs record <studio> start|end <runId>  -> grava snapshot de quota no ledger
// O consumo de um estúdio na semana = soma de (end - start) do % semanal, por run, desde o último reset.
// Runs simultâneos de estúdios diferentes contaminam a diferença; o manager despacha IA pesada um estúdio por vez.
import { readFileSync, appendFileSync, existsSync, mkdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHash } from 'node:crypto'
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
  const baselines = rows.filter((row) => row.phase === 'baseline')
  if (baselines.length) {
    if (baselines.length !== 1 || rows[0] !== baselines[0]) throw new Error('baseline duplicado ou fora de ordem')
    const baseline = baselines[0]
    const runtime = JSON.parse(readFileSync(join(ROOT, 'studios', studio, 'executor-runtime.json'), 'utf8'))
    const hash = createHash('sha256').update(raw.split('\n')[0]).digest('hex')
    const window = runtime.holding_window
    const stamp = Date.parse(baseline.measured_at)
    if (!window || window.id !== baseline.runId || window.baseline_sha256 !== hash || baseline.studio !== studio || baseline.provider !== key || baseline.historical_usage_pct !== null || baseline.authorization !== window.authorization || runtime.authorized_calls !== baseline.authorized_calls || runtime.authorized_tokens !== baseline.authorized_tokens || !Number.isFinite(stamp) || stamp > Date.now() || baseline.resets_at !== q[key]?.resets_at || Date.parse(q[key]?.measured_at) < stamp || typeof baseline.used_pct !== 'number' || !Number.isFinite(baseline.used_pct) || baseline.used_pct < 0 || baseline.used_pct > 100 || baseline.share_pct !== window.share_pct || typeof baseline.share_pct !== 'number' || baseline.share_pct <= 0 || baseline.share_pct > 100) throw new Error('baseline sem autorizacao valida para este studio/provedor/janela')
    if (q[key].used_pct < baseline.used_pct) throw new Error('quota regrediu desde o baseline')
    const starts = new Map(), ends = new Set()
    for (const row of rows.slice(1)) {
      if (row.studio !== studio || typeof row.runId !== 'string' || !row.runId || !Number.isFinite(Date.parse(row.at)) || Date.parse(row.at) < Date.parse(baseline.at) || Date.parse(row.at) > Date.now() || !['start','end'].includes(row.phase)) throw new Error('linha invalida apos baseline')
      if (row.phase === 'start') {
        if (starts.has(row.runId)) throw new Error('run duplicado')
        starts.set(row.runId, row)
      } else {
        const start = starts.get(row.runId)
        if (!start || ends.has(row.runId) || Date.parse(row.at) < Date.parse(start.at) || start[`${key}_resets_at`] !== baseline.resets_at || row[`${key}_resets_at`] !== baseline.resets_at || [start[`${key}_pct`], row[`${key}_pct`]].some((n) => typeof n !== 'number' || !Number.isFinite(n)) || row[`${key}_pct`] < start[`${key}_pct`]) throw new Error('fim desconhecido/invalido apos baseline')
        ends.add(row.runId)
      }
    }
    if ([...starts.keys()].some((id) => !ends.has(id))) throw new Error('run sem medicao final')
    return { used: q[key].used_pct - baseline.used_pct, cap: baseline.share_pct, id: baseline.runId }
  }
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
  let window = null
  try {
    if (typeof cap !== 'number' || !Number.isFinite(cap) || cap <= 0 || cap > 100) throw new Error('teto invalido')
    used = weeklyShareUsed(k)
    if (typeof used === 'object') { window = used; used = window.used }
  } catch (error) {
    reasons.push(`${k}: ${error.message}`)
    usage[k] = { used_pct_of_plan: null, cap_pct_of_plan: cap }
    if (verdict === 'OK') verdict = 'UNKNOWN'
    continue
  }
  usage[k] = window
    ? { used_pct_of_plan: null, historical_usage: 'unknown', window_id: window.id, used_pct_of_window: used, cap_pct_of_window: window.cap }
    : { used_pct_of_plan: used, cap_pct_of_plan: cap }
  // A janela autorizada nunca passa do teto do budget.json.
  if (used >= Math.min(window?.cap ?? cap, cap)) { reasons.push(`${studio}: orcamento de quota esgotado`); verdict = 'STOP' }
}
if (studio === 'website') reasons.push('builds de clientes seguem a demanda; o teto acima vale para trabalho de melhoria')

console.log(JSON.stringify({ verdict, studio, provider_scope: providers, reasons, usage, quota: q }, null, 2))
process.exit(verdict === 'OK' ? 0 : 3)
