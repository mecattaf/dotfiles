// ~/.agency/workflows/day-prep.workflow.js, the master agency's day prep (copy; the integrator copies it there).
// Tom, 10 Nov (journal/2026/11/10/start.md:72): "the above would be the "day prep" protocol, as something that can
// be done in the early morning to preempt me having to manually do it."
// Tom, 10 Nov 21:16Z (T23 item 8): "potentially also an llm-driven "next day prep" run that reads md files and jsonl
// chats. to be seen later."
// Started by a request to the superagent (docs/scheduled.md, "Day prep"), or by the off-by-default nudge
// .agency/scheduled/day-prep.jsonc. Each agent() call is one Ticket run in the master agency (cwd ~).
// Four readers read yesterday and change nothing; one writer writes the one file the day folder gains. The ~/today
// rollover is journal-day's job, not this one; a missing day folder means it has not run, and nothing is written.
export const meta = {
  name: 'day-prep',
  description: "Read yesterday's journal, Projects, closed chats and overnight runs; write today's day-prep.md as an assistant draft",
  phases: [{ title: 'read' }, { title: 'write' }],
}

const JOURNAL = '~/notes/journal'
const date = args && typeof args.date === 'string' ? args.date : ''
const ymd = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date)
const day = ymd && new Date(Date.UTC(Number(ymd[1]), Number(ymd[2]) - 1, Number(ymd[3])))
if (!day || day.toISOString().slice(0, 10) !== date) {
  throw new Error(`args.date must be the day to prepare as YYYY-MM-DD, got ${JSON.stringify(date)}`)
}
const prev = new Date(day.getTime() - 86400000).toISOString().slice(0, 10)
const folder = (d) => `${JOURNAL}/${d.replaceAll('-', '/')}`
const today = folder(date)
const yesterday = folder(prev)
const target = `${today}/day-prep.md`

const READ_ONLY = 'Change nothing: write, move or delete no file, run no command that changes state, and add, edit or close nothing in Projects.'
const POINTER = 'Personal, health, CRM and account material is pointer-only: name the file, never quote or summarize its content.'
const SOURCED = { type: 'string', description: 'The file path or command the item comes from' }
const items = (props) => ({
  type: 'array',
  items: { type: 'object', required: ['text', 'source'], properties: { text: { type: 'string' }, source: SOURCED, ...props } },
})

phase('read')
const READERS = ['journal', 'projects', 'chats', 'overnight']
const read = await parallel([
  () => agent(
    `Read the journal folder for ${prev}: ${yesterday}/. Read its top-level Markdown files and, in each subfolder, only README.md, MORNING-REPORT.md and BUILD-LOG.md; do not descend into salvage, checkpoint, donor or archive trees. ${READ_ONLY} ${POINTER} ` +
      'Report what ended (demonstrated outcomes), the decisions Tom stated in his own words, and what was left open. Keep Tom\'s words apart from assistant proposals: an item is Tom\'s only when the file quotes him.',
    { label: 'journal', schema: { type: 'object', required: ['ended', 'decisions', 'open'], properties: { ended: items(), decisions: items(), open: items() } } },
  ),
  () => agent(
    `Run \`project overview\` and read what it prints, as it stands on the morning after ${prev}. ${READ_ONLY} ` +
      'Report each item that waits on Tom (an answer, a ratification, a choice or a hand action) with the project it belongs to.',
    { label: 'projects', schema: { type: 'object', required: ['waiting'], properties: { waiting: items({ project: { type: 'string' } }) } } },
  ),
  () => agent(
    `Read ${yesterday}/raw-chat-index.jsonl if it exists: it points to the closed chat transcripts of ${prev} under ~/notes/archives/ai-chats/. Open at most 12 of the transcripts it points to, the longest first, and read only enough of each to name its topic and any question it left for Tom. If the index is missing, say so in one item and read nothing else. Never open a live session's files under ~/.claude*, ~/.codex or ~/.dsh. ${READ_ONLY} ` +
      `Chat content is pointer-only for personal, health, CRM and account material: ${POINTER}`,
    { label: 'chats', schema: { type: 'object', required: ['threads'], properties: { threads: items({ question: { type: 'string' } }) } } },
  ),
  () => agent(
    `Report the scheduled and floor work that ended between the start of ${prev} (Europe/Paris) and now. Run \`scheduled history -n 50 --json\` and \`dshd ls --json\`, and read nothing else. ${READ_ONLY} ` +
      'For each run say what it was and how it ended; list a run that failed, was refused or needs a decision under failures, with the reason its own output gives.',
    { label: 'overnight', schema: { type: 'object', required: ['ended', 'failures'], properties: { ended: items(), failures: items() } } },
  ),
])
const answers = Object.fromEntries(READERS.map((r, i) => [r, read[i]]))
const missing = READERS.filter((r) => answers[r] === null)
if (missing.length) log(`day-prep ${date}: no answer from ${missing.join(', ')}`)

phase('write')
const written = await agent(
  [
    `Write the day prep for ${date} as the one file ${target}.`,
    `If the folder ${today} does not exist, write nothing: the ~/today rollover has not run, and creating day folders is not this job. If ${target} already exists, write nothing: it may hold Tom's edits.`,
    'Otherwise write it with the first line exactly "# Assistant draft", then these sections, each a short list whose items name their source path or command: "What ended overnight", "What waits on Tom", "Failures needing a decision", "Threads from yesterday". An empty section says "Nothing found".',
    'Use only the readers\' answers below. This is an assistant draft, never in Tom\'s voice: quote Tom only where a reader quoted him, and keep proposals marked as proposals.',
    `${POINTER} Change no other file; never edit start.md.`,
    missing.length ? `No answer from: ${missing.join(', ')}. Say so in the first section that reader would have filled.` : 'Every reader answered.',
    `Readers' answers (JSON): ${JSON.stringify(answers)}`,
    `Reply with whether you wrote the file, its path (${target}), and the reason when you did not.`,
  ].join('\n'),
  { label: 'write', schema: { type: 'object', required: ['written', 'path', 'reason'], properties: { written: { type: 'boolean' }, path: { type: 'string' }, reason: { type: 'string' } } } },
)
if (written === null) log(`day-prep ${date}: no answer from the writer`)
return {
  date,
  path: target,
  written: written !== null && written.written === true,
  reason: written === null ? 'the writer gave no answer' : written.reason,
  missing,
}
