import type { Register } from 'claude-code'

// The help skill's fenced block under "## HELP": one source for both paths.
const helpFrom = (skill: string) =>
  skill.split('## HELP')[1]?.match(/```\n([\s\S]*?)\n```/)?.[1]

export const register: Register = on => {
  // A bare /executor:help prints the help with no model turn. With text after
  // it, or if the help can't be read, the skill runs and routes as before.
  on('command.run', { command: 'executor:help' }, async ($, e, next) => {
    if (e.args.trim() !== '') return next(e)

    const skill = await $.fs.read(`${$.plugin.root}/skills/help/SKILL.md`)
    const help = typeof skill === 'string' ? helpFrom(skill) : undefined

    return help ? { text: help } : next(e)
  }).catch(($, e, next) => next(e))
}
