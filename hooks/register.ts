import type { Register } from 'claude-code'

// The help skill's fenced block under "## HELP": one source for both paths.
const helpFrom = (skill: string) =>
  skill.split('## HELP')[1]?.match(/```\n([\s\S]*?)\n```/)?.[1]

// What a script printed; '' when it failed, timed out or printed nothing.
const printed = (run: Promise<{ exitCode: number; stdout: string }>) =>
  run.then(({ exitCode, stdout }) => (exitCode === 0 ? stdout.trimEnd() : '')).catch(() => '')

export const register: Register = on => {
  // A bare /executor:help prints the help with no model turn. With text after
  // it, or if the help can't be read, the skill runs and routes as before.
  on('command.run', { command: 'executor:help' }, async ($, e, next) => {
    if (e.args.trim() !== '') return next(e)

    const skill = await $.fs.read(`${$.plugin.root}/skills/help/SKILL.md`)
    const help = typeof skill === 'string' ? helpFrom(skill) : undefined

    if (!help) return next(e)

    const plans = await printed(
      $.process.run(['bash', `${$.plugin.root}/scripts/plan-path.sh`, '--summary'], { timeoutMs: 5000 }),
    )

    return { text: plans ? `${help}\n\n${plans}` : help }
  }).catch(($, e, next) => next(e))

  // A bare /executor:status prints the script's output with no model turn. With
  // text after it, or when the script gives nothing to show, the skill runs.
  on('command.run', { command: 'executor:status' }, async ($, e, next) => {
    if (e.args.trim() !== '') return next(e)

    const status = await printed($.process.run(['bash', `${$.plugin.root}/scripts/status.sh`], { timeoutMs: 15000 }))

    return status ? { text: status } : next(e)
  }).catch(($, e, next) => next(e))
}
