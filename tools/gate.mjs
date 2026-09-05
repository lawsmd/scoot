#!/usr/bin/env node
// gate.mjs - conventions gate: luacheck for broken references, plus grep
// patterns that catch a hand-rolled copy of a shared module or a comment that
// breaks the code hygiene rules.
//
// Runs from any directory; paths resolve against the addon root (the parent of
// this directory). Needs node and luacheck on the path.
//
//   node tools/gate.mjs                whole tree against tools/gate-baseline.txt
//   node tools/gate.mjs a.lua b.lua    the named files only
//   node tools/gate.mjs --update       rewrite the baseline from the tree as it is
//   node tools/gate.mjs --hook         PostToolUse hook: tool payload on stdin
//
// Exit 0 clean. Exit 1 a finding: a pattern count above its baseline row, or a
// luacheck error or undefined name. Exit 2 a stale baseline only: a count fell
// below its row, so run --update and commit the baseline with the change. Hook
// mode always exits 0 and reports through additionalContext.
//
// A hit is legitimate when the site carries a comment in the form
//   -- Kept off addon.<Module>: <reason>.
// and a baseline row. The baseline holds one row per pattern and file:
// pattern, path, count, tab-separated. Counts rather than line numbers, so an
// edit above a kept site does not churn it.

import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import { dirname, extname, isAbsolute, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const BASELINE = join(ROOT, 'tools', 'gate-baseline.txt')
const SKIP_AT_ROOT = new Set(['libs', '.git', 'tools'])
const LUACHECK_CODES = /\((E\d+|W11[123])\)/

// Each pattern guards one shared module. `except` lists the files that own the
// module; a hit there is the module itself.
const COMPOSITES = ['ui/v2/SettingsBuilder.lua', 'ui/v2/settings/BuilderComposites.lua']
const PATTERNS = [
  { name: 'event-frame', re: /:RegisterEvent\(|SetScript\("OnEvent"/, except: ['core/events.lua'],
    hint: 'Game events go through component:On or addon.Events.On; a private frame is for RegisterUnitEvent or a lift edge with no pending state.' },
  { name: 'hide-hook', re: /hooksecurefunc\([^,]+,\s*"(Show|Hide|SetAlpha|SetShown)"/, except: ['core/enforce.lua'],
    hint: 'A re-assert that keeps a region hidden is addon.Enforce.Set; a hook that mirrors or restyles is fine, mark it.' },
  { name: 'blizzard-pool', re: /\bCreate(Unsecured)?ObjectPool\(/, except: [],
    hint: 'Reusable frames come from addon.Pool.New or addon.Pool.NewIndexed.' },
  { name: 'class-color-table', re: /\b(RAID_CLASS_COLORS|CUSTOM_CLASS_COLORS|PowerBarColor)\b/, except: ['core/colors.lua'],
    hint: 'Class and power colors come from addon.GetClassColorRGB and addon.GetPowerColorRGB; the tables are read in core/colors.lua only.' },
  { name: 'color-switch', re: /colorMode\s*==\s*"(class|custom|default|texture)"/, except: ['core/colors.lua'],
    hint: 'A colorMode switch is addon.ResolveColorRGBA(mode, tint, opts).' },
  { name: 'opacity-field', re: /[.:]\s*(opacityInCombat|opacityWithTarget|opacityOutOfCombat|barOpacityInCombat|barOpacityOutOfCombat)\b/, except: ['core/opacity.lua', 'ui/v2/settings/BuilderComposites.lua'],
    hint: 'Opacity keys are read through addon.Opacity.Resolve, Opacity.DeclaresAny, or an Opacity.Keys map.' },
  { name: 'dump-guard', re: /if addon\.DebugShowWindow then/, except: [],
    hint: 'addon.DebugShowWindow always exists; drop the guard and its print fallback.' },
  { name: 'newline-join', re: /table\.concat\([^)]*"\\n"\)/, except: [],
    hint: 'A debug dump passes the lines table to addon.DebugShowWindow; a joined string is right for an export payload, mark it.' },
  { name: 'print', re: /(^|[^_A-Za-z.:])print\(/, except: [],
    hint: 'Never print to chat; addon.DebugShowWindow shows a copyable window.' },
  { name: 'slash-global', re: /^\s*SLASH_[A-Z0-9_]+\s*=|SlashCmdList[.[]/, except: ['Scoot.lua'],
    hint: 'Commands register with addon:RegisterSlashCommand or addon:RegisterDebugCommand at the end of the file that owns the handler.' },
  { name: 'text-block', re: /:AddFontSelector\(/, except: COMPOSITES,
    hint: 'A font, style, size, color, alignment, offset block is Builder:AddTextStyleBlock.' },
  { name: 'dual-slider', re: /:AddDualSlider\(/, except: COMPOSITES,
    hint: 'An X/Y or H/V pair is Builder:AddOffsetPair or Builder:AddInsetPair; two unrelated quantities stay a dual slider, mark it.' },
  { name: 'bar-selector', re: /:AddBar(Texture|Border)Selector\(/, except: COMPOSITES,
    hint: 'Bar style and border rows are Builder:AddBarStyleBlock and Builder:AddBarBorderBlock.' },
  { name: 'clamp-hook', re: /hooksecurefunc\([^,]+,\s*"(SetClampedToScreen|SetClampRectInsets)"/, except: ['core/editmode/offscreenunlock.lua'],
    hint: 'Clamp enforcement is a family from addon.OffscreenUnlock.NewFamily; the hooks live in core/editmode/offscreenunlock.lua only.' },
  { name: 'art-alpha', re: /return .*useCustomBorders.*and 0 or 1/, except: ['core/components/unitframes/bars/alpha.lua'],
    hint: 'A Use Custom Borders alpha closure is Alpha.customBordersAlpha(unit, withHideBorder) in bars/alpha.lua.' },
  { name: 'popup-list', re: /closeListener/, except: ['ui/v2/controls/Utils.lua'],
    hint: 'Click-outside dismissal is Controls.AttachDismissOnClickOutside; a selector option list is Controls.CreatePopupList.' },
  // Comment hygiene: the greps the vibes pass runs.
  { name: 'doc-ref', re: /ADDONCONTEXT|[a-z0-9_&-]+\.md\b|wow-ui-source/i, except: [],
    hint: 'Shipped code names no internal doc, doc path, or reference tree.' },
  { name: 'first-person', re: /^\s*--.*\b(we|our|us|ours|ourselves)\b/i, except: [],
    hint: 'Comments are impersonal.' },
  { name: 'dated', re: /\b20(25|26)-[0-9]{2}-[0-9]{2}|user decision|\((user|maintainer)[,)]/i, except: [],
    hint: 'Comments carry no dates, decisions, or attributions.' },
  { name: 'filler', re: /--.*\b(actually|actual|attempts?|a little|sufficient|remainder|kind of|robust|utilize|leverage|seamless)\b/i, except: [],
    hint: 'Filler words: state the fact.' },
  { name: 'claims', re: /--.*\b(verified live|verified in-game|measured [0-9]|user report|user spec|reference addons)\b/i, except: [],
    hint: 'No verification claims or report attributions in comments.' },
  { name: 'competitor', re: /nephui|elvui|unhalted|arcui|dandersframes|ellesmere|coolinator|tweaksui|quazii|\boUF\b/i, except: [],
    hint: 'No other addon names in code.' },
  { name: 'staging', re: /lands in Phase|HOLDING[0-9]|left beta/i, except: [],
    hint: 'No staging notes in code.' },
]

const GUIDANCE = [
  'Fix the site, or when it stays off the module on purpose mark it with a `-- Kept off addon.<Module>: <reason>.` comment',
  'and add its row with `node tools/gate.mjs --update`. A stale row means hits went away: run --update and commit tools/gate-baseline.txt.',
]

function rel (abs) {
  return relative(ROOT, abs).split('\\').join('/')
}

function listLua (dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (dir === ROOT && SKIP_AT_ROOT.has(name)) continue
    const p = join(dir, name)
    const st = statSync(p)
    if (st.isDirectory()) listLua(p, out)
    else if (extname(name).toLowerCase() === '.lua') out.push(p)
  }
  return out
}

function scan (files) {
  const counts = new Map()
  for (const file of files) {
    const path = rel(file)
    let text
    try { text = readFileSync(file, 'utf8') } catch { continue }
    const lines = text.split(/\r?\n/)
    for (const p of PATTERNS) {
      if (p.except.includes(path)) continue
      let n = 0
      for (const line of lines) if (p.re.test(line)) n++
      if (n) counts.set(`${p.name}\t${path}`, n)
    }
  }
  return counts
}

function readBaseline () {
  const map = new Map()
  if (!existsSync(BASELINE)) return map
  for (const line of readFileSync(BASELINE, 'utf8').split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue
    const [name, path, count] = line.split('\t')
    if (name && path && count) map.set(`${name}\t${path}`, Number(count))
  }
  return map
}

function writeBaseline (counts) {
  const rows = [...counts.entries()]
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([key, n]) => `${key}\t${n}`)
  const head = [
    '# gate-baseline.txt - known hits per pattern and file, tab-separated.',
    '# Written by `node tools/gate.mjs --update`; commit it with the change that moved a count.',
    '# A row is a site that stays off a shared module on purpose (it carries a Kept off comment) or drift not yet fixed.',
  ]
  writeFileSync(BASELINE, head.concat(rows, '').join('\n'))
  return rows.length
}

function compare (counts, baseline, scanned) {
  const findings = []
  const stale = []
  for (const [key, n] of counts) {
    const b = baseline.get(key) || 0
    if (n > b) findings.push({ key, n, b })
    else if (n < b) stale.push({ key, n, b })
  }
  for (const [key, b] of baseline) {
    if (!scanned.has(key.split('\t')[1])) continue
    if (!counts.has(key)) stale.push({ key, n: 0, b })
  }
  return { findings, stale }
}

function luacheck (files) {
  const args = (files.length ? files.map(rel) : ['.']).concat(['--no-color', '--formatter', 'plain', '--codes'])
  const r = spawnSync('luacheck', args, { cwd: ROOT, encoding: 'utf8', windowsHide: true })
  if (r.error) return { missing: true, lines: [] }
  const lines = (r.stdout || '').split(/\r?\n/).filter(l => LUACHECK_CODES.test(l))
  return { missing: false, lines }
}

function run (files) {
  const targets = files.length ? files : listLua(ROOT)
  const scanned = new Set(targets.map(rel))
  const { findings, stale } = compare(scan(targets), readBaseline(), scanned)
  const luac = luacheck(files)
  return { findings, stale, luac }
}

function describe ({ findings, stale, luac }) {
  const hintOf = name => (PATTERNS.find(p => p.name === name) || {}).hint || ''
  const out = []
  for (const f of findings) {
    const [name, path] = f.key.split('\t')
    out.push(`  ${name}  ${path}  ${f.n} hit${f.n === 1 ? '' : 's'}, baseline ${f.b}`)
    out.push(`      ${hintOf(name)}`)
  }
  for (const l of luac.lines) out.push(`  luacheck  ${l}`)
  for (const s of stale) {
    const [name, path] = s.key.split('\t')
    out.push(`  stale  ${name}  ${path}  ${s.n} hit${s.n === 1 ? '' : 's'}, baseline ${s.b}`)
  }
  return out
}

function verdict (r) {
  if (r.findings.length || r.luac.lines.length) return 1
  if (r.stale.length) return 2
  return 0
}

function hook () {
  let payload
  try { payload = JSON.parse(readFileSync(0, 'utf8')) } catch { return }
  const named = payload?.tool_input?.file_path
  if (!named) return
  const abs = isAbsolute(named) ? named : resolve(payload?.cwd ?? ROOT, named)
  if (extname(abs).toLowerCase() !== '.lua') return
  const r = rel(abs)
  if (r.startsWith('..') || isAbsolute(r) || r.startsWith('libs/')) return
  if (!existsSync(abs)) return

  const result = run([abs])
  if (verdict(result) === 0) return

  const context = [
    'Conventions gate (node tools/gate.mjs) on the Lua file just written:',
    ...describe(result),
    '',
    ...GUIDANCE,
  ].join('\n')
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: context },
  }))
}

function cli (argv) {
  if (argv.includes('--update')) {
    const n = writeBaseline(scan(listLua(ROOT)))
    console.log(`gate: baseline written, ${n} rows`)
    return 0
  }
  const files = argv.filter(a => !a.startsWith('--')).map(a => resolve(process.cwd(), a))
  for (const f of files) {
    if (!existsSync(f)) { console.error(`gate: no such file ${f}`); return 1 }
  }
  const result = run(files)
  if (result.luac.missing) console.log('gate: luacheck not found on the path; pattern checks only')
  const code = verdict(result)
  if (code === 0) {
    console.log(`gate: clean (${files.length ? files.length + ' file(s)' : 'whole tree'})`)
    return 0
  }
  const n = result.findings.length + result.luac.lines.length
  console.log(`gate: ${n} finding${n === 1 ? '' : 's'}, ${result.stale.length} stale row${result.stale.length === 1 ? '' : 's'}`)
  for (const line of describe(result)) console.log(line)
  for (const line of GUIDANCE) console.log(line)
  return code
}

if (process.argv.includes('--hook')) {
  try { hook() } catch { /* a broken check must never cost a write */ }
  process.exit(0)
} else {
  process.exit(cli(process.argv.slice(2)))
}
