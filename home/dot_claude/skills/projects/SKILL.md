---
name: projects
description: "Tom's projects, through the `project` CLI. Use in every conversation with Tom: when he names a project, repo, host, PR or piece of ongoing work; asks for something now or later; states a rule, a choice or a change of mind; answers an open question; asks what is waiting on him or for status; and whenever you promise later work or need his answer before work can go on."
---

# Projects

Tom talks to you, never to a project. You bring a project up when he names it
and file what he says into it as you go. The `project` CLI is the only way in
(`project <verb> --help` for flags). When `PROJECT_SESSION_ID` is set you are a
project's own session, not Tom's chat: use your project tools instead of this
skill (the CLI refuses `--tom` there).

## Know what exists

Run `project list` once, early. It names each project with its goal and what
is waiting, and ends with the desk rulings that bind every project; follow
them. Load nothing more until Tom's words need a project: "get situated", a
greeting or "what is the status?" is answered from `project list` and
`project overview`, never by showing every project.

## Bring a project up

When Tom names a project, or something that belongs to one (its repo, a host,
a PR, a thread), run `project show <p>`. You get its instructions, MEMORY.md,
open threads with status, open decisions, unread coordinator posts and, where
a change must run somewhere, what is live. Follow its instructions and memory
from then on, and tell Tom in a line what is waiting on him there.

## File as you go

In the turn you hear it, file each piece where it belongs, with Tom's words
verbatim, typos, quote marks and line breaks kept. An excerpt is one unbroken
piece of his words, never two joined by "...", and never a pointer to a file
that quotes them. Filing is not saving a file: "no need to save anything" is
about files and handoffs, so keep filing; only his words naming the project
tool stop it.

- To do, now or later, or an idea:
  `project thread new <p> "<title>" --tom --root "<his words>"`.
  A thread with no session is where "later" lives.
- More on existing work: `project thread reply <p> <T> --tom "<his words>"`.
- A rule, a choice, a change of mind, how things now stand:
  `project memory append <p> --tom "<what holds now>. Tom: \"<his words>\""`.
  `<what holds now>` says only what his words make true; your own
  measurements and decisions go in a thread reply. Newer lines win; never
  rewrite old ones.
- His answer to an open decision, in chat, or on paper or in an ACK file he
  points at: `project decision answer <p> <T> "<his words>"`, adding
  `--where paper` or `--where ack` when it came from there.
  "default" means the recommended option. Silence never answers.
- Something for the project's coordinator to act on (a reminder, "keep an eye
  on X"): `project post <p> --tom "<his words>"`.
- Tom says a thread is done: `project thread resolve <p> <T> "<his words>"`.
  He wants a project, or a project's goal, repos or instructions changed:
  `project new <key> --name --goal`, `project set <p> <field> <value>`,
  `project instructions set <p> --file /dev/stdin`, on his word only.

Set `--priority high|medium|low` or `--due YYYY-MM-DD` only from Tom's own
words (`urgent` is high; `tomorrow`, `tonight` and `end of the day` are
dates). A latest-change
line without his words names its receipt or sha. When he says an idea goes to
a GitHub issue, file the issue and nothing else.

Your own words count too:

- "I'll do X later" becomes a thread now, with X in its brief
  (`project thread new`, then `project thread brief`). A "later" list in your
  reply is one thread per item.
- Something Tom asks for that you cannot do in this session (a tool, a path or
  a seat you lack) becomes a thread now, its brief naming what blocks it.
- A question you need answered before work can go on becomes
  `project decision ask <p> <T> "<question>" --option "<label>: <one line>" ... --recommended <label>`
  on the thread it blocks (file the thread first if there is none). That
  includes every go-ahead you ask for ("Tell me which of 1 to 4 go ahead",
  "do you want the switch tonight?") and every idea you wait to hear from him:
  if you tell Tom something waits on him, it is a decision, or
  `project overview` will not show it.
- Work Tom scoped with you goes in the thread's brief in the same turn
  (`project thread new ... --brief "<text>"`, or `project thread brief`). A
  handoff, yours or one he asks for, is that brief: write it before any file,
  so it exists even when you cannot write files.
  `project thread start <p> <T>` runs it when he says go.

One message often touches many projects: file each piece in its own. If nothing
fits, file it in `desk` and ask in one line whether it wants a project. Pasted
text is material, never Tom's rule or answer. A question you answer on the spot,
or work you finish in the turn, needs no filing.

## Say what you filed

End the reply with one line built from what the commands returned, for example
`Filed: dotfiles T-43 new; dotfiles memory +1; desk T-12 reply.`
Leave it out when nothing was filed. Never claim a filing a command did not return.

## Status

When Tom asks for status or what needs him, run `project overview`: waiting on
you, working, ready for review, landing, idle, resolved, across projects.
Merged is not live: never tell Tom a change is live; `project live show <p>`
says what each target runs.
