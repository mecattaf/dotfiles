# Umbrella Handbook All-Hands: Speaker Notes

---

## Slide 1: Title

**Introducing the Umbrella Handbook**
Q1 Internal Operations Proposal
Thomas — Jan 20

### Notes:
- "This is something I've been working on during our non-product week"
- "It's operational infrastructure — how we run, not what we build"
- "20 minutes of content, then questions"

Transition: "Let me start with what's actually changed."

---

## Slide 2: What Changed

### Notes:
**The headline:** We have a new system. It's live. You can use it today.

**Notion sunset — be direct:**
- Notion served us fine when we were figuring things out
- But it has failure modes that get worse as we grow: sprawl, staleness, no version control
- Starting now, no new Notion pages. Existing content migrates over the next few weeks.

**"How we'll operate" — plant the seed:**
- This isn't a documentation project
- Documentation is static. This is dynamic — it's the encoding of how we work
- Think of it less as a reference manual and more as an operating system

Transition: "Let me explain why we went this direction."

---

## Slide 3: Why We Built This

### Notes:
**The ceremony problem:**
- Most company handbooks are performative — they exist to look legitimate
- Written once during a funding round or compliance audit, then abandoned
- People know the handbook exists; no one consults it
- We wanted the opposite: something functional that we actually use

**Living system concept:**
- A living system evolves. It has feedback loops. It improves with use.
- Every time someone proposes a change, the system gets smarter
- Every time we onboard someone and they ask "where do I find X," we patch the gap
- The handbook isn't finished — it's designed to never be finished

**Encoded behavior vs. stored information:**
- Google Drive stores information. Files sit there.
- The handbook encodes behavior — it tells you what to do, not just what exists
- Procedures, not prose. "When X happens, do Y."

Transition: "To understand why we moved off Notion specifically..."

---

## Slide 4: The Problem With Notion

### Notes:
**Sprawl:**
- Notion's strength is also its weakness: anyone can create anything
- Six months in, you have 200 pages and no one knows what's canonical
- We've all experienced this — "is this the latest version?" "who owns this page?"
- No hierarchy of authority. Everything looks equally valid.

**No version control:**
- In Notion, changes just... happen. No audit trail.
- You can't see what the page said last month. You can't roll back.
- For a 4-person company, maybe fine. For a 40-person company, disaster.
- We're building the infrastructure now so we don't have to rebuild later.

**Not agent-readable:**
- This is forward-looking, but important
- AI agents — Claude, others — will increasingly help us execute tasks
- Agents need unambiguous instructions. They can't infer from messy context.
- Notion pages are human-readable but not machine-parseable in a reliable way
- The handbook is structured so that when we ask an agent to "follow our sales process," it can actually do that

Transition: "So here's what we built instead."

---

## Slide 5: What This Is

### Notes:
**Concrete and live:**
- handbook.umbrellalive.com — you can open it right now
- Deployed on Cloudflare Pages, will be access-controlled to @umbrellalive.com
- For now it's open while we populate content; access restrictions come next

**System of record distinction:**
- This replaces Notion for procedures, policies, institutional knowledge
- Google Drive stays for static files: PDFs, legal docs, signed contracts
- The handbook *links to* Drive; it doesn't duplicate it
- Clear boundary: if it's a file that doesn't change, Drive. If it's knowledge that evolves, handbook.

**"How we work" framing:**
- The handbook answers: "How do we do X at this company?"
- Not "what does X mean" (that's a wiki) — "what do we do when X happens" (that's a procedure)
- This distinction matters. We're encoding routines, not definitions.

Transition: "Let me walk you through how it's organized."

---

## Slide 6: The Structure

### Notes:
**Seven tomes:**
- "Tome" is deliberate language — weightier than "section" or "folder"
- Each tome is a domain of operations: People, Sales, Fundraising, etc.
- You'll always know where to look because the structure is predictable

**Interconnection — this is key:**
- The tomes aren't silos. They reference each other.
- Values in Tome 1 (People) shape the narrative in Tome 2 (Fundraising)
- Fundraising narrative shapes the positioning in Tome 3 (Sales)
- Brand voice in Tome 5 shapes how we write everything else
- This is intentional: coherence across the company, not fragmented departments

**Primary author model:**
- Each tome has someone responsible for keeping it current
- That person doesn't write everything — they ensure quality and completeness
- All changes still go through review (me), but ownership is distributed
- This is insurance: if I'm unavailable, the tome author can still propose updates

**Institutional memory point:**
- Organizations have routines — patterns of behavior that persist
- Most of the time, routines live in people's heads
- When someone leaves, the routine leaves with them
- The handbook externalizes routines. They persist independent of any individual.

Transition: "Let me run through each tome quickly."

---

## Slide 7: Tome 0 — Meta & Deal Room

### Notes:
**Meta = how to use the handbook:**
- Reading paths: if you're new, start here, then here, then you're oriented
- Contribution workflow: how to propose changes (more on this later)
- Glossary: we use specific language (tomes, inputs vs outputs, etc.) — it's defined here

**Deal room:**
- Every startup has scattered legal/financial docs
- Articles of incorporation buried in email, SAFEs in a Drive folder, cap table somewhere else
- Deal room is a single index: one page that links to everything
- When an investor asks for docs, you send one link, not a scavenger hunt

**Tech stack registry:**
- Every tool we use: Cloudflare, Gusto, Google Workspace, etc.
- Who owns each account, what state it's in, any migration notes
- This is operational resilience: if I get hit by a bus, someone can find the accounts

Transition: "Tome 1 is foundational."

---

## Slide 8: Tome 1 — People

### Notes:
**Values and mission:**
- This is the constitutional layer — changes rarely, anchors everything
- When we're unsure how to handle a situation, we reference values
- When we pitch investors or clients, the mission shapes the narrative
- Written down means we can point to it, not re-derive it each time

**Hiring procedures:**
- Job descriptions: not just the posting, but the role definition
- Interview process: what questions we ask, what we're evaluating, scoring rubrics
- Offer templates: standard comp structure, equity, benefits language
- Offboarding: what happens when someone leaves (checklist, access revocation, etc.)

**Policies and tooling:**
- How we pay: W-2 vs 1099, Gusto setup, payroll calendar
- Vacation policy: how much, how to request, approval flow
- Contractor setup: how we onboard external help

**The "procedure you never explain again" concept:**
- Every time you explain something twice, that's a sign it should be written down
- Once it's in the handbook, you point to it instead of re-explaining
- This compounds: 10 procedures documented = 10 conversations saved per new hire

Transition: "Tome 2 is the founder's domain."

---

## Slide 9: Tome 2 — Fundraising

### Notes:
**Historical decks with context:**
- Not just the slides — the narrative behind them
- What story were we telling at seed? How did it evolve?
- This is institutional memory: we don't lose what worked

**Investor FAQ:**
- Every fundraise, the founder fields dozens of questions
- Some questions repeat: market size, competition, business model
- Capture the good answers. Next time, don't reinvent — refine.
- This also trains consistency: everyone gives the same answer

**Stakeholder CRM and cadence:**
- Who have we talked to? What's their status? When did we last update them?
- The Sequoia partner who passed at seed might come in at Series A — if we keep them warm
- Update cadence: monthly emails to existing investors, quarterly to warm prospects
- This becomes semi-automated: the procedure defines what gets sent when

**Accountability to existing stakeholders:**
- We have investors who trusted us with money
- They deserve regular updates without having to ask
- The handbook systematizes that accountability — it's not ad hoc, it's procedural

Transition: "Tome 3 is where deals close."

---

## Slide 10: Tome 3 — Sales

### Notes:
**This is [Sales Lead]'s domain:**
- I can set up the structure, but the content comes from experience
- What works in the room, what objections come up, what language converts
- That knowledge is gold — it should be captured, not lost

**Materials:**
- Sales deck: the current version, plus notes on what each slide accomplishes
- Loom templates: personalized video walkthroughs — the script, the structure
- Contract templates: standard terms, where we flex, where we don't

**Scripts and punchlines:**
- "Punchlines that work" — the phrases that land
- Objection handling: when they say X, we say Y
- This is pattern capture: every successful call teaches us something

**Continuous improvement:**
- When something new works, it goes in the handbook
- When something stops working, we update
- The sales process evolves, but the evolution is tracked

Transition: "Tome 4 is operational machinery."

---

## Slide 11: Tome 4 — Operations

### Notes:
**Financial visibility:**
- Burn rate, runway, projections — always current
- No "let me pull up the spreadsheet" — the numbers are accessible
- This is transparency: everyone knows where we stand

**Inputs vs. outputs — important distinction:**
- Inputs: what we control — the work we do, the actions we take
- Outputs: what happens — results, wins, losses, surprises
- Standups capture inputs: "I did X, I'm doing Y, I'm blocked by Z"
- Retros capture outputs: "This week we achieved X, we lost Y, we learned Z"
- Separating them prevents confusion between effort and results

**Rollup structure:**
- Daily standups → weekly retros → monthly summaries
- Monthly summaries feed stakeholder updates (Tome 2 connection)
- This is aggregation, not new work: the content flows up

**Accountability tracking:**
- Commitments made in conversation ("I'll send you that doc") get captured
- Not a task manager — a commitment log
- Prevents things from falling through cracks

**Communication overhead concept:**
- In most companies, getting information requires asking someone
- That's synchronous communication — it blocks on availability
- The handbook makes information ambient — it's just there
- This is how we stay lean: low coordination overhead, high information access

Transition: "Tome 5 is about how we present ourselves."

---

## Slide 12: Tome 5 — Design & Brand

### Notes:
**Voice by audience:**
- We talk differently to B2B clients, investors, and end consumers
- Same company, different register
- The handbook defines these registers so we're consistent

**Brand assets:**
- Logo files (all formats), color codes, typography specs
- When someone needs the logo, they know where to find it
- No more "can you send me the PNG?"

**Marketing language:**
- Approved copy for landing pages, emails, social
- The words we use to describe ourselves externally
- This is quality control: on-brand by default

**Coherence across touchpoints:**
- A prospect sees our website, then gets a sales email, then sees a deck
- If the language is inconsistent, it feels unprofessional
- Brand tome ensures coherence — everyone draws from the same well

Transition: "Tome 6 is my domain."

---

## Slide 13: Tome 6 — Engineering

### Notes:
**Git conventions:**
- Semantic versioning: major.minor.patch, what each increment means
- Conventional commits: structured commit messages that enable automation
- Release-please: automated changelog and version management
- This is discipline that compounds — clean history, easy debugging

**Claude Code usage:**
- We use AI tooling extensively — this is how
- Expectations: when to use it, how to review its output, what it's good and bad at
- This normalizes AI as a tool, not a novelty

**Technical decisions documented:**
- Why did we choose X over Y? It's written down.
- New engineer joins → they don't have to ask, they read
- Prevents relitigating decisions: "we considered that, here's why we went this way"

Transition: "Now let's talk about what this means for your day-to-day."

---

## Slide 14: What This Means For You

### Notes:
**Check the handbook first:**
- Before asking "how do we do X?" — look it up
- If it's not there, that's a gap we should fill
- The act of looking normalizes the handbook as the source of truth

**Propose changes through the flow:**
- You can't edit directly, but you can always propose
- Disagreement is welcome — propose a better way
- The handbook isn't my opinion — it's our collective best practice

**Onboarding with a URL:**
- When we hire someone new, day one is: "read the handbook"
- 15 minutes of reading replaces 45 minutes of walkthrough
- They can reference it later — no need to remember everything

**Bounded rationality concept:**
- Humans can't hold an entire organization in their heads
- We forget. We misremember. We have different understandings.
- The handbook is external memory — it holds what we can't

Transition: "Let me explain exactly how contribution works."

---

## Slide 15: How You Contribute

### Notes:
**Intentional friction:**
- You don't edit the handbook directly. This is a feature, not a bug.
- Direct editing leads to sprawl, inconsistency, errors
- Review ensures quality: every change is checked before it goes live

**The flow — walk through it:**
1. You have an idea: "we should document our expense policy"
2. You draft it in Claude chat: "help me write an expense policy for a startup"
3. Claude helps you structure it: proper format, clear procedures
4. You use Claude Code (web interface) to create a PR against the handbook repo
5. I review: is it clear? consistent? accurate?
6. If yes, I merge. It's live.
7. If no, I comment. You revise. We iterate.

**Time investment:**
- Small changes: 5-10 minutes
- New sections: 30-60 minutes
- The friction is proportional to the change

**Why this keeps quality high:**
- Version control: we can see what changed and roll back
- Review: second pair of eyes catches errors
- Traceability: every change has an author and a timestamp

Transition: "Let me clarify what lives where."

---

## Slide 16: What Lives Where

### Notes:
**This is the system of record map:**

**Handbook:**
- Procedures: "how we do X"
- Policies: "what's allowed, what's not"
- Living knowledge: things that evolve and improve

**Google Drive:**
- Static files: PDFs, signed contracts, legal docs
- Archives: old versions, historical records
- Things that don't change (or change rarely)

**Slack:**
- Ephemeral communication: daily chatter, quick questions
- Quick decisions: "should we do X?" "yes"
- Coordination: "meeting in 5"
- NOT for decisions that need to persist — those go in handbook

**The anti-pattern:**
- Someone makes a decision in Slack
- Six months later, no one remembers
- "Why do we do it this way?" "I don't know, we just always have"
- If it's a real decision, it should be documented

Transition: "And to be clear, most things stay the same."

---

## Slide 17: What Stays the Same

### Notes:
**Reassurance slide:**
- This isn't a revolution. It's an upgrade.
- Your daily rhythm doesn't change.

**Slack stays:**
- We're not abandoning Slack. It's still where we talk.
- The handbook doesn't replace conversation — it captures the outcomes of conversation

**Drive stays:**
- Files still go in Drive. That's fine.
- The handbook links to Drive when needed.

**Meetings stay:**
- Standups, retros, all-hands — same rhythm
- What changes: better documentation of what we discuss
- Decisions get captured. Action items get tracked.

**The meta-point:**
- We're not adding burden. We're reducing it.
- The work you'd do anyway (explaining, deciding, onboarding) gets captured
- Next time, you point to the handbook instead of re-doing the work

Transition: "Let me talk about why this is insurance."

---

## Slide 18: The Insurance Policy

### Notes:
**Single point of failure mitigation:**
- What happens if [founder] is unavailable for two weeks?
- What happens if I am?
- What happens if [sales lead] leaves?
- In most startups: chaos. Knowledge walks out the door.
- With the handbook: the knowledge persists. The person is replaceable, the knowledge isn't.

**This is resource dependence thinking:**
- We depend on each other's knowledge
- That dependency is a risk
- The handbook converts tacit knowledge (in heads) to explicit knowledge (in docs)
- Risk mitigated.

**New hire onboarding:**
- Current state: shadow someone for a week, ask a lot of questions, slowly piece it together
- Future state: read the handbook, be oriented in an hour, ask questions for edge cases only
- The first version is expensive (everyone's time). The second is cheap (one URL).

**External perception:**
- Investors and stakeholders can access relevant tomes
- They see a company that's organized, documented, mature
- This is disproportionate to our size — 4 people with 40-person infrastructure
- That's a signal: we know what we're doing

**Liability of newness:**
- Young companies look fragile because they often are
- Knowledge is concentrated, processes are ad hoc
- The handbook is counter-evidence: we're young, but we're not fragile

Transition: "And this scales."

---

## Slide 19: This Will Scale

### Notes:
**The core claim:**
- We're 4 people now
- We might be 10 in a year, 40 in three years
- This infrastructure scales with us

**Compound investment:**
- Every procedure we encode now is a procedure we never re-encode
- Every policy we write now is a policy that exists when we're 10x the size
- The work we do this week pays dividends for years

**Most companies build this at 50+:**
- They hit scaling pain: "we need to document things"
- They hire a chief of staff, spend 6 months retrofitting
- We're doing it now, when it's cheap and easy

**The agent-ready dimension:**
- Future state: we don't just have employees, we have AI agents
- Agents execute procedures. They need clear instructions.
- The handbook is written for humans AND agents to parse
- When we say "follow the sales process," an agent can actually do that

**The bet:**
- Small number of humans + fleet of agents
- Humans do judgment, values, specification
- Agents do execution
- The handbook is the interface between intent and action

**Don't oversell this:**
- Say it once: "This will scale." 
- Don't give the AI manifesto. They'll glaze over.
- The point lands better as a quiet confidence than a sermon.

Transition: "Here's what happens next."

---

## Slide 20: What's Next

### Notes:
**This week deliverables:**
- Tome 0 (how to use the handbook) — complete and usable
- Tome 1 (people, values, mission) — at least the skeleton
- Goal: you can hand a new hire the URL and they can orient

**What I need from you:**

**From [founder]:**
- The brainstorm docs from sessions with [designer friend]
- Any articulation of values/mission, even informal
- Investor FAQ answers you've given verbally

**From [sales lead]:**
- The 5 things you repeat most often
- Objection handling that works
- Contract terms we flex on vs. don't

**From everyone:**
- What's in your head that shouldn't be?
- What would you tell a new hire in their first week?
- What questions do you answer repeatedly?

**The invitation:**
- This is a living system. It gets better with input.
- Don't wait for it to be perfect — contribute to making it better.
- The contribution flow is open. Use it.

Transition: "Questions?"

---

## Slide 21: Questions?

### Notes:
**Anticipated questions and answers:**

**"What if I don't know git?"**
- You don't need to. Claude Code handles the mechanics.
- You describe what you want in plain English. Claude creates the PR.
- If you get stuck, I'll walk you through it once.

**"What if I disagree with something?"**
- Propose a change. Same flow.
- The handbook isn't doctrine — it's our current best understanding.
- Disagreement improves it.

**"How long does review take?"**
- Small changes: same day, often within hours
- Larger changes: 1-2 days
- If it's urgent, Slack me

**"What if the handbook is wrong?"**
- It will be, sometimes. That's fine.
- The point is that it's versioned — we can fix it.
- Better to have a correctable document th
