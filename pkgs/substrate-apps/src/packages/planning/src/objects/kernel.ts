/**
 * The Kernel object: one per executor, and the only thing that talks to one.
 *
 * A kernel is any executor implementing the admit-and-witness contract with its
 * own single-writer hash chain. The local rail on the coordinator is one; a
 * cloud-side executor running a harness in a sandbox is another. The lake keeps
 * one of these objects per executor, keyed by its `ExecutorId`, and nothing
 * above it assumes there is exactly one.
 *
 * The Worker calls the box. Admits, cancels, steers and capacity requests go
 * down as calls this object makes against the executor's endpoint — for the
 * local rail, a hostname on Tom's zone fronted by a tunnel to the coordinator,
 * with a shared secret the link checks on every call and no Access in front of
 * it. Witness records, heartbeats, doubts and capacity readings come up as posts
 * the executor makes to the Worker with the same secret. The secret lives in the
 * link's Layer and appears in no value here, so nothing that handles a message
 * can store, log or mirror it.
 *
 * This object carries messages and holds a little state. It makes no release
 * decision: keeping the decision in the Factory and the sending here is what
 * stops a placement decision hiding inside a release decision. It never retries
 * a *rejected* admit either, because a repair attempt is a new item with its own
 * key and never a schedule wrapping a node.
 *
 * What it does retry is a send that never arrived. An unreachable executor is
 * the ordinary case, not the exceptional one, so an admit that could not be
 * delivered is queued in order and re-sent on the object's alarm. It is never
 * dropped, never re-decided, and never replaced by an invented one — the lake's
 * whole job is to lose nothing that was armed.
 *
 * The three admit outcomes are idempotent and one of them is not a failure.
 * `NotYet` means the payload goes back to the lake untouched: deferring is not
 * scheduling, and this object treats it exactly as it treats an empty pass.
 */
import { Context, Effect, Layer, Option, Ref } from "effect";
import type { Admit, AdmitOutcome, Cancel, Steer } from "../schema/admit.ts";
import type { CapacityReading } from "../schema/capacity.ts";
import { KernelLinkError } from "../schema/errors.ts";
import type { ExecutorId, TaskId } from "../schema/ids.ts";
import type { Verdict } from "../schema/records.ts";
import type { Doubt, Heartbeat, UpMessage } from "../schema/uplink.ts";

/**
 * The wire to one executor.
 *
 * Four calls down and four messages up, which is the whole contract. The
 * production Layer holds the endpoint and the shared secret and speaks HTTPS
 * through the tunnel; the fake Layer below answers from a script. Both cross
 * this interface, so a test that passes here is not passing because the link was
 * lenient.
 *
 * The up half is a drain rather than a callback: the uplink posts to the Worker,
 * the Worker hands what arrived to the object, and the object folds it. Modelled
 * this way, nothing in the lake can subscribe to an executor's live plane and
 * quietly become a second scheduler — there is no stream to react to, only
 * messages that have already been posted.
 */
export interface IKernelLink {
  /** Which executor this link addresses. */
  readonly executor: ExecutorId;
  /** Sends one admit and waits for the door's answer. */
  readonly admit: (admit: Admit) => Effect.Effect<AdmitOutcome, KernelLinkError>;
  /**
   * Sends one cancel.
   *
   * Only a human or an armed supersession authorises one; the lake never
   * originates a cancel of its own, and the message carries which of the two
   * authorised it.
   */
  readonly cancel: (cancel: Cancel) => Effect.Effect<void, KernelLinkError>;
  /**
   * Delivers one steer into a live pane, populate and never submit.
   *
   * The durable half of a steer — the amendment that moves a task's epoch — is
   * the lake's own state. This is only the delivery, and the executor's blocked
   * interlock binds it exactly as it binds Tom at the keyboard.
   */
  readonly steer: (steer: Steer) => Effect.Effect<void, KernelLinkError>;
  /**
   * Asks for a fresh capacity reading.
   *
   * The lake asks when a state change makes the answer worth having. There is no
   * interval behind this call and no loop that issues it.
   */
  readonly capacityRequest: Effect.Effect<CapacityReading, KernelLinkError>;
  /**
   * Takes the up-messages the executor has posted since the last drain.
   *
   * Witness records, heartbeats, doubts and capacity readings, in the order they
   * were posted. Every herdr-shaped observation the estate produces arrives
   * here, because tally wraps herdr and this package never speaks to it.
   */
  readonly drainUp: Effect.Effect<ReadonlyArray<UpMessage>, KernelLinkError>;
}

/** Provides the wire to one executor. */
export class KernelLink extends Context.Service<KernelLink, IKernelLink>()(
  "@substrate/planning/KernelLink"
) {}

/** What the Kernel object holds between wake-ups. */
interface KernelState {
  /** Which executor this object fronts. */
  readonly executor: ExecutorId;
  /** The most recent reading, or `None` before the first one arrives. */
  readonly lastReading: Option.Option<CapacityReading>;
  /** Admits sent, accepted, and not yet answered by a witness. */
  readonly inFlight: ReadonlyArray<TaskId>;
  /**
   * Admits that could not be delivered, in the order they were decided.
   *
   * The alarm retries them. An unreachable executor holds work; it never loses
   * it, and the lake never re-decides in the meantime.
   */
  readonly queued: ReadonlyArray<Admit>;
  /**
   * Lanes this executor has reported blocked on a human.
   *
   * herdr's single `blocked` state, carried as an observation. It is what the
   * andon reads and it is never promoted to a verdict.
   */
  readonly blocked: ReadonlyArray<TaskId>;
  /**
   * How far the object has consumed the executor's offline queue.
   *
   * An executor that ran while the lake was unreachable mirrors its work up on
   * reconnect; the cursor is how the object knows what it has already seen.
   */
  readonly offlineCursor: number;
}

/** What one dispatch pass did. */
interface DispatchReport {
  /** The answers the door gave, for the admits that reached it. */
  readonly outcomes: ReadonlyArray<AdmitOutcome>;
  /** The admits that could not be delivered and are now queued for the alarm. */
  readonly queued: ReadonlyArray<Admit>;
}

/** One executor's Kernel object. */
interface IKernel {
  /**
   * Records a capacity reading.
   *
   * Readings are ordered by their sequence number and an out-of-order reading is
   * dropped rather than applied, because a stale reading that overwrote a fresh
   * one would let the engine admit against capacity that is already spent.
   *
   * @returns whether the reading was taken.
   */
  readonly observeCapacity: (
    reading: CapacityReading
  ) => Effect.Effect<boolean, KernelLinkError>;
  /** The most recent reading. */
  readonly lastReading: Effect.Effect<Option.Option<CapacityReading>, KernelLinkError>;
  /** Asks the executor for a fresh reading and records it. */
  readonly requestCapacity: Effect.Effect<CapacityReading, KernelLinkError>;
  /**
   * Sends admits down the wire in order.
   *
   * Stops sending at the first transport failure and queues the rest, because a
   * send whose arrival is ambiguous must not be followed by more sends against
   * headroom it may already have consumed. Nothing is discarded: what was not
   * sent is returned and held for the alarm.
   */
  readonly dispatch: (
    admits: ReadonlyArray<Admit>
  ) => Effect.Effect<DispatchReport, never>;
  /**
   * Re-sends the queued admits, as the alarm does.
   *
   * Idempotent by the dedup key, which is what makes a retry safe after an
   * ambiguous failure.
   */
  readonly retryQueued: Effect.Effect<DispatchReport, never>;
  /** Sends one authorised cancel. */
  readonly cancel: (cancel: Cancel) => Effect.Effect<void, KernelLinkError>;
  /** Delivers one steer into a live pane. */
  readonly steer: (steer: Steer) => Effect.Effect<void, KernelLinkError>;
  /**
   * Folds one up-message into the object's state.
   *
   * A witness clears an in-flight admit and advances the offline cursor; a doubt
   * marks a lane blocked; a heartbeat is liveness and changes nothing but the
   * cursor; a reading is recorded under the staleness rule.
   */
  readonly receive: (message: UpMessage) => Effect.Effect<void, KernelLinkError>;
  /** Drains what the executor posted and folds all of it. */
  readonly drain: Effect.Effect<ReadonlyArray<UpMessage>, KernelLinkError>;
  /** The object's current state. */
  readonly state: Effect.Effect<KernelState, KernelLinkError>;
}

/** Provides one executor's Kernel object. */
export class Kernel extends Context.Service<Kernel, IKernel>()("@substrate/planning/Kernel") {}

/**
 * Constructs one executor's Kernel object while preserving its link requirement.
 *
 * @param executor - Which executor this object fronts. One object per executor,
 *   always: two executors behind one object would be two doors behind one key,
 *   and an atomic multi-row admission would stop being atomic.
 */
export const makeKernel = (executor: ExecutorId) =>
  Effect.gen(function* () {
    const link = yield* KernelLink;
    const state = yield* Ref.make<KernelState>({
      executor,
      lastReading: Option.none(),
      inFlight: [],
      queued: [],
      blocked: [],
      offlineCursor: 0
    });

    const takeReading = (reading: CapacityReading) =>
      Ref.modify(state, (current) => {
        const stale = Option.match(current.lastReading, {
          onNone: () => false,
          onSome: (previous) => reading.seq <= previous.seq
        });
        if (stale) return [false, current] as const;
        return [true, { ...current, lastReading: Option.some(reading) }] as const;
      });

    const observeVerdict = (verdict: Verdict) =>
      Ref.update(state, (current) => ({
        ...current,
        inFlight: current.inFlight.filter((taskId) => taskId !== verdict.taskId),
        blocked: current.blocked.filter((taskId) => taskId !== verdict.taskId),
        offlineCursor: Math.max(current.offlineCursor, verdict.seq)
      }));

    const observeDoubt = (doubt: Doubt) =>
      Ref.update(state, (current) => ({
        ...current,
        blocked: current.blocked.includes(doubt.taskId)
          ? current.blocked
          : [...current.blocked, doubt.taskId],
        offlineCursor: Math.max(current.offlineCursor, doubt.seq)
      }));

    const observeHeartbeat = (heartbeat: Heartbeat) =>
      Ref.update(state, (current) => ({
        ...current,
        offlineCursor: Math.max(current.offlineCursor, heartbeat.seq)
      }));

    const receive = (message: UpMessage): Effect.Effect<void, KernelLinkError> => {
      switch (message._tag) {
        case "Verdict":
          return observeVerdict(message);
        case "Doubt":
          return observeDoubt(message);
        case "Heartbeat":
          return observeHeartbeat(message);
        case "CapacityReading":
          return Effect.asVoid(takeReading(message.reading));
      }
    };

    /**
     * Sends a run of admits, stopping at the first transport failure.
     *
     * The remainder is queued rather than attempted, and rather than dropped.
     */
    const send = (
      admits: ReadonlyArray<Admit>
    ): Effect.Effect<DispatchReport, never> =>
      Effect.gen(function* () {
        const outcomes: Array<AdmitOutcome> = [];
        for (const [index, admit] of admits.entries()) {
          // The failure is captured rather than raised: an unreachable executor
          // is an ordinary state of the world, and the queue is the response to
          // it. Raising here would make the caller decide what to do with work
          // that has already been decided.
          const answer = yield* Effect.result(link.admit(admit));
          if (answer._tag === "Failure") {
            const remainder = admits.slice(index);
            yield* Ref.update(state, (current) => ({
              ...current,
              queued: [...current.queued, ...remainder]
            }));
            return { outcomes, queued: remainder } satisfies DispatchReport;
          }
          outcomes.push(answer.success);
          if (answer.success._tag === "Accepted") {
            yield* Ref.update(state, (current) => ({
              ...current,
              inFlight: [...current.inFlight, admit.taskId]
            }));
          }
        }
        return { outcomes, queued: [] };
      });

    return Kernel.of({
      observeCapacity: Effect.fn("Kernel.observeCapacity")(function* (
        reading: CapacityReading
      ) {
        return yield* takeReading(reading);
      }),

      lastReading: Ref.get(state).pipe(Effect.map((current) => current.lastReading)),

      requestCapacity: Effect.gen(function* () {
        const reading = yield* link.capacityRequest;
        yield* takeReading(reading);
        return reading;
      }),

      dispatch: (admits: ReadonlyArray<Admit>) => send(admits),

      retryQueued: Effect.gen(function* () {
        // Taken out of the queue before the attempt, so a failure re-queues the
        // remainder exactly once rather than doubling it.
        const pending = yield* Ref.modify(state, (current) => [
          current.queued,
          { ...current, queued: [] as ReadonlyArray<Admit> }
        ]);
        return yield* send(pending);
      }),

      cancel: (cancel: Cancel) => link.cancel(cancel),

      steer: (steer: Steer) => link.steer(steer),

      receive,

      drain: Effect.gen(function* () {
        const messages = yield* link.drainUp;
        for (const message of messages) yield* receive(message);
        return messages;
      }),

      state: Ref.get(state)
    });
  });

/** Provides one executor's Kernel object without selecting a link. */
const kernelLayerWithoutDependencies = (
  executor: ExecutorId
): Layer.Layer<Kernel, never, KernelLink> => Layer.effect(Kernel, makeKernel(executor));

/** How the fake link should answer one call. */
interface FakeLinkScript {
  /** Which executor the fake fronts. */
  readonly executor: ExecutorId;
  /**
   * How to answer an admit.
   *
   * Defaults to accepting. A test that needs a rejection or a deferral supplies
   * its own answer, so no test passes because the fake silently absorbed a
   * refusal.
   */
  readonly onAdmit?: (admit: Admit) => AdmitOutcome;
  /**
   * Whether the executor is reachable.
   *
   * `false` fails every call with `Unreachable`, which is what exercises the
   * queue-and-retry path. This is the ordinary offline case, not a fault
   * injection.
   */
  readonly reachable?: boolean;
  /** The reading `capacityRequest` answers with, when the executor is reachable. */
  readonly reading?: CapacityReading;
  /** The messages a drain returns, once, in order. */
  readonly up?: ReadonlyArray<UpMessage>;
}

/** What a fake link recorded, for a test to assert against. */
interface FakeLinkLog {
  /** Admits that reached the door. */
  readonly admits: ReadonlyArray<Admit>;
  /** Cancels delivered. */
  readonly cancels: ReadonlyArray<Cancel>;
  /** Steers delivered. */
  readonly steers: ReadonlyArray<Steer>;
  /** How many capacity requests were made. */
  readonly capacityRequests: number;
}

/** A fake link, with the log it wrote. */
interface FakeLink {
  /** The link itself, ready to provide. */
  readonly link: IKernelLink;
  /** What it recorded. */
  readonly log: Effect.Effect<FakeLinkLog>;
}

/**
 * Constructs an in-memory link to a fabricated executor.
 *
 * Behaviourally faithful rather than a partial mock: it enforces the same
 * ordering, records what it was asked to send, and fails every call when the
 * executor is unreachable, which is what lets the queue-and-retry path be tested
 * without a network.
 *
 * @param script - How this executor should answer.
 */
export const makeFakeKernelLink = (
  script: FakeLinkScript
): Effect.Effect<FakeLink> =>
  Effect.gen(function* () {
    const admits = yield* Ref.make<ReadonlyArray<Admit>>([]);
    const cancels = yield* Ref.make<ReadonlyArray<Cancel>>([]);
    const steers = yield* Ref.make<ReadonlyArray<Steer>>([]);
    const requests = yield* Ref.make(0);
    const up = yield* Ref.make<ReadonlyArray<UpMessage>>(script.up ?? []);

    const reachable = script.reachable ?? true;
    const unreachable = <A>(): Effect.Effect<A, KernelLinkError> =>
      Effect.fail(
        new KernelLinkError({
          reason: "Unreachable",
          executor: script.executor,
          // A call that never left cannot have arrived, which is the one case
          // where the retry partition is answerable with certainty.
          mayHaveArrived: false
        })
      );

    const link: IKernelLink = {
      executor: script.executor,
      admit: (admit: Admit) =>
        reachable
          ? Ref.update(admits, (current) => [...current, admit]).pipe(
              Effect.as(
                script.onAdmit?.(admit) ?? {
                  _tag: "Accepted" as const,
                  taskId: admit.taskId
                }
              )
            )
          : unreachable<AdmitOutcome>(),
      cancel: (cancel: Cancel) =>
        reachable
          ? Ref.update(cancels, (current) => [...current, cancel])
          : unreachable<void>(),
      steer: (steer: Steer) =>
        reachable
          ? Ref.update(steers, (current) => [...current, steer])
          : unreachable<void>(),
      capacityRequest: reachable
        ? Ref.update(requests, (count) => count + 1).pipe(
            Effect.flatMap(() =>
              script.reading === undefined
                ? Effect.fail(
                    new KernelLinkError({
                      reason: "ProtocolViolation",
                      executor: script.executor,
                      mayHaveArrived: true
                    })
                  )
                : Effect.succeed(script.reading)
            )
          )
        : unreachable<CapacityReading>(),
      drainUp: reachable
        ? Ref.modify(up, (current) => [current, [] as ReadonlyArray<UpMessage>])
        : unreachable<ReadonlyArray<UpMessage>>()
    };

    return {
      link,
      log: Effect.all({
        admits: Ref.get(admits),
        cancels: Ref.get(cancels),
        steers: Ref.get(steers),
        capacityRequests: Ref.get(requests)
      })
    };
  });

/** Provides a fake link to one fabricated executor. */
const fakeKernelLinkLayer = (script: FakeLinkScript): Layer.Layer<KernelLink> =>
  Layer.effect(
    KernelLink,
    makeFakeKernelLink(script).pipe(Effect.map((fake) => KernelLink.of(fake.link)))
  );

/** Provides one executor's Kernel object over a fake link, for tests. */
export const kernelTestLayer = (script: FakeLinkScript): Layer.Layer<Kernel> =>
  kernelLayerWithoutDependencies(script.executor).pipe(
    Layer.provide(fakeKernelLinkLayer(script))
  );
