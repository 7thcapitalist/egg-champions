#!/usr/bin/env node
// Mede a quota SEMANAL das assinaturas a partir de arquivos locais, sem chamar API nenhuma.
// - Codex: último evento `rate_limits` (limit_id "codex") nos logs de sessão em ~/.codex/sessions.
// - Claude: ~/.habblaud/usage/<conta>.json, gravado pelo mod do Habblaud a cada resposta do Claude Code.
// Saída: JSON { codex: {used_pct, resets_at, measured_at, age_min, source}, claude: {...} } (null se sem medição).
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { homedir } from 'node:os'

const HOME = process.env.USERPROFILE || process.env.HOME || homedir()
const now = Date.now()

function newestFiles(dir, ext, limit) {
  const out = []
  const walk = (d) => {
    let entries
    try { entries = readdirSync(d, { withFileTypes: true }) } catch { return }
    for (const e of entries) {
      const p = join(d, e.name)
      if (e.isDirectory()) walk(p)
      else if (e.name.endsWith(ext)) out.push({ p, m: statSync(p).mtimeMs })
    }
  }
  walk(dir)
  return out.sort((a, b) => b.m - a.m).slice(0, limit)
}

function codexQuota() {
  const codexHome = process.env.CODEX_HOME || join(HOME, '.codex')
  for (const { p, m } of newestFiles(join(codexHome, 'sessions'), '.jsonl', 20)) {
    const lines = readFileSync(p, 'utf8').trim().split('\n').reverse()
    for (const line of lines) {
      if (!line.includes('"rate_limits"')) continue
      let ev
      try { ev = JSON.parse(line) } catch { continue }
      const rl = ev?.payload?.rate_limits ?? ev?.rate_limits ?? ev?.payload?.info?.rate_limits
      if (!rl || (rl.limit_id && rl.limit_id !== 'codex')) continue
      const weekly = [rl.primary, rl.secondary].find((w) => w && w.window_minutes >= 7 * 24 * 60) ?? rl.primary
      if (!weekly) continue
      const measured = ev.timestamp ? Date.parse(ev.timestamp) : m
      return {
        used_pct: weekly.used_percent,
        resets_at: weekly.resets_at ? new Date(weekly.resets_at * 1000).toISOString() : null,
        measured_at: new Date(measured).toISOString(),
        age_min: Math.round((now - measured) / 60000),
        plan: rl.plan_type ?? null,
        paid_credits: rl.credits?.has_credits ?? null,
        source: p,
      }
    }
  }
  return null
}

function claudeQuota() {
  const dir = process.env.HABBLAUD_USAGE_DIR || join(HOME, '.habblaud', 'usage')
  if (!existsSync(dir)) return null
  let best = null
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.json'))) {
    let rec
    try { rec = JSON.parse(readFileSync(join(dir, f), 'utf8')) } catch { continue }
    const w = rec.seven_day
    if (!w || typeof w.utilization !== 'number') continue
    const measured = rec.fetchedAt ? (rec.fetchedAt > 1e12 ? rec.fetchedAt : rec.fetchedAt * 1000) : statSync(join(dir, f)).mtimeMs
    const cand = {
      used_pct: w.utilization,
      five_hour_pct: rec.five_hour?.utilization ?? null,
      resets_at: w.resets_at ? new Date(w.resets_at * 1000).toISOString() : null,
      measured_at: new Date(measured).toISOString(),
      age_min: Math.round((now - measured) / 60000),
      source: join(dir, f),
    }
    if (!best || cand.used_pct > best.used_pct) best = cand
  }
  return best
}

const result = { measured: new Date(now).toISOString(), codex: codexQuota(), claude: claudeQuota() }
if (import.meta.url === `file:///${process.argv[1].replace(/\\/g, '/')}` || process.argv[1]?.endsWith('quota.mjs')) {
  console.log(JSON.stringify(result, null, 2))
}
export { codexQuota, claudeQuota }
