# Takahashi-method decks

Guidelines for authoring a Takahashi-style deck within presentation-beta.

## The method

- **One idea per slide, one word if you can.** Each slide carries a single word or
  short phrase — never a sentence, never a list.
- **Set it enormous.** The text is scaled to fill the viewport. The word *is* the slide;
  there is no title/body hierarchy because there is no body.
- **Many slides, rapid pace.** A Takahashi talk burns through slides fast — the deck is
  long, each slide is on screen for seconds. Advancing is punctuation for the speech.
- **No bullets, no images, no charts** in the pure form. No decoration. The slide is a
  visual drumbeat behind the spoken narration, not a document that stands on its own.
- **The slide supports the voice.** All meaning lives in what the speaker says; the slide
  just anchors the current beat.

## When to choose it

- Talks with a strong spoken narrative and rehearsed pacing.
- High-energy delivery where you want the room watching you, not reading the screen.
- Conceptual or persuasive talks that don't lean on data.

## When NOT to

- Data-heavy decks (metrics, comparisons, diagrams) — use the standard design references.
- Reference decks meant to be read async or handed out — a Takahashi deck is meaningless
  without its speaker.

## Mapping to presentation-beta (reveal.js)

- **One `<section>` per word/phrase.** The deck is just many minimal sections.
- **Scale text to fill the viewport** — a single large element per slide, centered, using
  viewport-relative sizing (e.g. `font-size: 20vw`) so the word dominates the screen.
- **Speaker notes carry ALL the content.** This fits presentation-beta's existing
  doctrine: the sidecar `.md` holds the speaker notes (one `### Notes` block per slide).
  In a Takahashi deck the notes aren't supplementary — they're the entire talk, since the
  slide itself is just a cue word.

## Lineage

Takahashi method — devised by Masayoshi Takahashi. `tmcw/big` is a well-known web
implementation of the same one-huge-word-per-slide idea.
