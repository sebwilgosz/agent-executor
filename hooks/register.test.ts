import { expect, test } from 'claude-code/testing'

// A help skill in the shape the hook reads; scripts/self-audit.sh checks the
// real one keeps that shape.
const SKILL = '---\nname: help\n---\n# EXECUTOR\n\n## HELP\n\nShow this:\n\n```\n1. REVIEW → /executor:review\n```\n\n## Routing\n'
const SKILL_RAN = 'the skill ran'

test('a bare /executor:help prints the help block without the skill', async ($, on) => {
  on('fs.read', () => ({ value: SKILL }))
  on('command.run', () => ({ text: SKILL_RAN }))

  const { text } = await $.command.run({ command: 'executor:help', args: '' })

  expect(text).toBe('1. REVIEW → /executor:review')
})

test('text after /executor:help goes to the skill', async ($, on) => {
  on('fs.read', () => ({ value: SKILL }))
  on('command.run', () => ({ text: SKILL_RAN }))

  const { text } = await $.command.run({ command: 'executor:help', args: 'review 42' })

  expect(text).toBe(SKILL_RAN)
})

test('a help skill without its "## HELP" block goes to the skill', async ($, on) => {
  on('fs.read', () => ({ value: '# EXECUTOR\n\nno help block here\n' }))
  on('command.run', () => ({ text: SKILL_RAN }))

  const { text } = await $.command.run({ command: 'executor:help', args: '' })

  expect(text).toBe(SKILL_RAN)
})

test('a bare /executor:help ends with where this repo\'s plans live', async ($, on) => {
  on('fs.read', () => ({ value: SKILL }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: 'PLANS:\n  folder /plans (default)\n', stderr: '' } }))

  const { text } = await $.command.run({ command: 'executor:help', args: '' })

  expect(text).toBe('1. REVIEW → /executor:review\n\nPLANS:\n  folder /plans (default)')
})

test('the help still prints when the plans summary fails', async ($, on) => {
  on('fs.read', () => ({ value: SKILL }))
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: 'boom' } }))

  const { text } = await $.command.run({ command: 'executor:help', args: '' })

  expect(text).toBe('1. REVIEW → /executor:review')
})

const STATUS = 'EXECUTOR STATUS\n\nacme/api\n  2026-11-07 - a plan\n    MOVING\n      Stack A: 1 not started'

test('a bare /executor:status prints what status.sh prints, without the skill', async ($, on) => {
  const runs: { argv: string[] }[] = []
  on('process.run', (_, e) => {
    runs.push(e)
    return { value: { exitCode: 0, stdout: `${STATUS}\n`, stderr: '' } }
  })
  on('command.run', () => ({ text: SKILL_RAN }))

  const { text } = await $.command.run({ command: 'executor:status', args: '  ' })

  expect(text).toBe(STATUS)
  expect(runs.length).toBe(1)
  expect(runs[0].argv.length).toBe(2)
  expect(runs[0].argv[0]).toBe('bash')
  expect(runs[0].argv[1].endsWith('/scripts/status.sh')).toBe(true)
})

test('text after /executor:status goes to the skill, with no script run', async ($, on) => {
  let ran = 0
  on('process.run', () => {
    ran++
    return { value: { exitCode: 0, stdout: STATUS, stderr: '' } }
  })
  on('command.run', () => ({ text: SKILL_RAN }))

  const { text } = await $.command.run({ command: 'executor:status', args: 'what blocks acme/api?' })

  expect(text).toBe(SKILL_RAN)
  expect(ran).toBe(0)
})

test('a non-zero exit from status.sh goes to the skill, even with output', async ($, on) => {
  on('process.run', () => ({ value: { exitCode: 1, stdout: STATUS, stderr: 'boom' } }))
  on('command.run', () => ({ text: SKILL_RAN }))

  const { text } = await $.command.run({ command: 'executor:status', args: '' })

  expect(text).toBe(SKILL_RAN)
})

test('empty output from status.sh goes to the skill', async ($, on) => {
  on('process.run', () => ({ value: { exitCode: 0, stdout: '', stderr: '' } }))
  on('command.run', () => ({ text: SKILL_RAN }))

  const { text } = await $.command.run({ command: 'executor:status', args: '' })

  expect(text).toBe(SKILL_RAN)
})

test('blank output from status.sh goes to the skill', async ($, on) => {
  on('process.run', () => ({ value: { exitCode: 0, stdout: ' \n\n', stderr: '' } }))
  on('command.run', () => ({ text: SKILL_RAN }))

  const { text } = await $.command.run({ command: 'executor:status', args: '' })

  expect(text).toBe(SKILL_RAN)
})

test('status.sh still running after 15 s goes to the skill', async ($, on) => {
  const limits: number[] = []
  on('process.run', (_, e) => {
    limits.push(e.init.timeoutMs)
    return { deny: 'still running after 15000ms' }
  })
  on('command.run', () => ({ text: SKILL_RAN }))

  const { text } = await $.command.run({ command: 'executor:status', args: '' })

  expect(text).toBe(SKILL_RAN)
  expect(limits).toEqual([15000])
})
