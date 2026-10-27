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
