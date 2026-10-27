import type { Register } from 'claude-code'

// The menu skill's fenced block under "## MENU": one source for both paths.
const menuFrom = (skill: string) =>
  skill.split('## MENU')[1]?.match(/```\n([\s\S]*?)\n```/)?.[1]

export const register: Register = on => {
  // A bare /executor:menu prints the menu with no model turn. With text after
  // it, or if the menu can't be read, the skill runs and routes as before.
  on('command.run', { command: 'executor:menu' }, async ($, e, next) => {
    if (e.args.trim() !== '') return next(e)

    const skill = await $.fs.read(`${$.plugin.root}/skills/menu/SKILL.md`)
    const menu = typeof skill === 'string' ? menuFrom(skill) : undefined

    return menu ? { text: menu } : next(e)
  }).catch(($, e, next) => next(e))
}
