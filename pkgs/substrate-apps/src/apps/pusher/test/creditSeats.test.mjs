// 2026-09-30: credit-metered seats through the gentle pusher. The oracle (`seats --json`, seat-capacity/1) states a
// credit counter for pi-qwencloud (local plan ratio), openrouter (the key's USD usage under a soft cap) and
// openrouter-free (the free model's daily request quota); the pusher carries it as the /2 `credits` key, gives each
// configured seat its slot count, and the floor's admitSeat admits on the counter.
import { Schema } from "effect"
import { describe, expect, it } from "vitest"

import { SeatCapacitySnapshot } from "@substrate/planning/schema/seatCapacity.ts"
import { admitSeat } from "@substrate/planning/capacity/project.ts"
import { decidePush, fingerprint, stateAfterPush } from "../src/seatCapacity.mjs"
import { snapshotFromSeatsV1 } from "../src/seatsOracle.mjs"

const NOW = "2026-09-30T20:00:00Z"

const doc = (over = {}) => ({
  schema_version: "seat-capacity/1",
  generated_at: "2026-09-30T19:59:30Z",
  host: "coordinator",
  seats: [
    {
      id: "pi-qwencloud", provider: "qwen", owner: "tom", grade: "ESTIMATED", state: "open", usable: true,
      source: { kind: "429-refusal-text", key_source: "/run/agenix/qwencloud-token" },
      credits: { allowance: 10000, used: 1534, remaining: 8466, tokens_per_credit: 192.5, basis: "input + output" },
      windows: [{ id: "qwen:weekly", minutes: 10080, scope: null, used_pct: 15.34, resets_at: "2026-10-03T10:22:17Z", severity: "" }]
    },
    {
      id: "openrouter", provider: "openrouter", owner: "tom", grade: "MEASURED", state: "open", usable: true,
      source: { kind: "openrouter-credits-endpoint", reading_age_seconds: 0 },
      credits: { unit: "usd", used: 1.25, limit: 12, counter: "provider", resets_at: null },
      windows: []
    },
    {
      id: "openrouter-free", provider: "openrouter", owner: "tom", grade: "MEASURED", state: "open", usable: true,
      source: { kind: "openrouter-key-endpoint", reading_age_seconds: 0 },
      credits: { unit: "requests", used: 10, limit: 1000, counter: "provider", resets_at: "2026-10-01T00:00:00Z" },
      windows: []
    },
    { id: "gpu-worker", provider: "halogen", owner: "kernel", grade: "MEASURED", state: "open", windows: [], source: {} },
    ...(over.extra ?? [])
  ]
})

const config = {
  seats: ["cc2", "pi-qwencloud", "openrouter", "openrouter-free", "halogen"],
  slots: { halogen: 1, "pi-qwencloud": 4, openrouter: 4, "openrouter-free": 8 },
  estimatedProviders: ["qwen"]
}

const bySeat = (snapshot) => Object.fromEntries(snapshot.seats.map((s) => [s.seat, s]))

describe("credit seats through the pusher", () => {
  it("carries each counter and slot count, and the snapshot decodes as seat-capacity/2", () => {
    const { snapshot } = snapshotFromSeatsV1(doc(), config, NOW)
    Schema.decodeUnknownSync(SeatCapacitySnapshot)(snapshot)
    const s = bySeat(snapshot)
    expect(s["pi-qwencloud"]).toMatchObject({
      grade: "ESTIMATED",
      slots: { capacity: 4, holders: 0 },
      credits: { unit: "credits", used: 1534, limit: 10000, resets_at: "2026-10-03T10:22:17Z", basis: "plan-ratio" }
    })
    expect(s.openrouter).toMatchObject({ grade: "MEASURED", slots: { capacity: 4, holders: 0 }, credits: { unit: "usd", used: 1.25, limit: 12, resets_at: null, basis: "provider" } })
    expect(s["openrouter-free"]).toMatchObject({ slots: { capacity: 8, holders: 0 }, credits: { unit: "requests", limit: 1000, basis: "provider" } })
    expect(s.halogen).toMatchObject({ slots: { capacity: 1, holders: 0 } })
    expect(s.halogen.credits).toBeUndefined()
    // Nothing else from the oracle's credits object (the key's path, the token ratio) leaves the box.
    expect(JSON.stringify(snapshot)).not.toContain("agenix")
    expect(JSON.stringify(snapshot)).not.toContain("tokens_per_credit")
  })

  it("the floor's rule admits all three on their counters", () => {
    const { snapshot } = snapshotFromSeatsV1(doc(), config, NOW)
    const decoded = Schema.decodeUnknownSync(SeatCapacitySnapshot)(snapshot)
    for (const seat of decoded.seats.filter((s) => s.credits !== undefined)) {
      expect(admitSeat(seat.seat, seat, { model: null, min_headroom_pct: 5 }, NOW)).toMatchObject({ admit: true, grade: "MEASURED-CREDIT" })
    }
  })

  it("an unreadable counter is left out (the seat then refuses as before), and an UNKNOWN seat carries none", () => {
    const d = doc()
    d.seats[1] = { ...d.seats[1], credits: { unit: "usd", used: "a lot", limit: 12 } }
    d.seats[2] = { ...d.seats[2], grade: "UNKNOWN" }
    const s = bySeat(snapshotFromSeatsV1(d, config, NOW).snapshot)
    expect(s.openrouter.credits).toBeUndefined()
    expect(admitSeat("openrouter", s.openrouter, { model: null, min_headroom_pct: 5 }, NOW)).toMatchObject({ admit: false, reason: "no-binding-window" })
    expect(s["openrouter-free"].credits).toBeUndefined()
  })

  it("a moving counter is a changed reading, and a credit seat keeps the slot heartbeat", () => {
    const a = snapshotFromSeatsV1(doc(), config, NOW).snapshot
    const d = doc()
    d.seats[1] = { ...d.seats[1], credits: { ...d.seats[1].credits, used: 2.5 } }
    const b = snapshotFromSeatsV1(d, config, NOW).snapshot
    expect(fingerprint(bySeat(a).openrouter)).not.toBe(fingerprint(bySeat(b).openrouter))
    const state = stateAfterPush(a, NOW)
    expect(decidePush(state, b, Date.parse(NOW) + 120_000)).toMatchObject({ push: true, reason: "changed", changed: ["openrouter"] })
    // Unchanged for 600 s: re-sent on the slot beat so the floor's copy stays MEASURED.
    const noHalogen = { ...a, seats: a.seats.filter((s) => s.provider !== "halogen") }
    expect(decidePush(stateAfterPush(noHalogen, NOW), noHalogen, Date.parse(NOW) + 600_000)).toMatchObject({ push: true, reason: "heartbeat" })
  })
})
