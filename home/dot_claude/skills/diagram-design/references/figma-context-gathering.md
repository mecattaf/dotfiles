<!-- Local graft. Adapted from figma-generate-diagram (figma-plugin-jun2026), Mermaid/FigJam plumbing stripped. -->

# Gather real context before diagramming

Garbage in, garbage out. The quality of a diagram is bounded by the quality of what you
feed it, which is bounded by the context you actually have. Before drawing any schematic,
make sure you have enough real information to describe the subject accurately — and use
whatever the current environment gives you to gather it.

Useful sources of ground truth, depending on what's available:

- **Source code** — grep/read the relevant files so the diagram reflects real service
  names, real edge labels, real data stores, real entry points. Walking actual
  routes/handlers/consumers beats reconstructing from memory.
- **User-provided documents** — a PRD, spec, meeting notes, transcript, research synthesis,
  onboarding doc, process write-up. Ask the user to paste or attach it if the subject
  isn't code.
- **Existing diagrams/design files** — if the new diagram should align with one the user
  already has, read it first so names and structure match.
- **Other tools you have available** — issue trackers, docs sites, database schemas,
  internal wikis, design systems. If a connected tool holds the ground truth for what
  you're diagramming, pull from it rather than guessing.
- **The user themselves** — when the description is thin or ambiguous (unclear direction of
  flow, unclear scope, unclear which entities matter), ask one or two focused questions
  before drawing. "What are the 3–5 main steps?", "Who owns each step?", "What triggers the
  next step?" One good question beats one wasted diagram.

**Don't invent edges, labels, or entities to "round out" a diagram.** Missing information is
better than hallucinated information — leave a gap and flag it to the user. A diagram that
confidently shows a connection that doesn't exist is worse than one that admits it doesn't
know.
