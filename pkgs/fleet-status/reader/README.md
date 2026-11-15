# Fleet status reader and scoped publisher

This directory extends the existing fleet-status package. The NAS observer
owns collection and public projection. These Workers retain and present one
self-contained public snapshot; they never query the NAS, invoke models,
inspect private files, or expose fleet controls.

`fleet-status-reader` serves the three static files and only
`GET/HEAD /api/v1/status.json` and `/api/v1/catalog.json`. The catalogue is
projected from the same committed `v1/status.json` object as the status response.
No object listing, arbitrary path, URL proxy or history route is exposed.

Connection state compares Worker time with R2's trusted upload timestamp:
connected through 180 seconds, disconnected afterward, retaining the original
snapshot and source timestamps. Snapshot/source clocks never establish a
heartbeat. Missing storage data returns HTTP200 with `uninitialized` and
`snapshot:null`; storage failure or invalid retained data returns safe HTTP503.
Status responses have a maximum15-second public cache lifetime. The browser
refreshes every15seconds and uses only text nodes for snapshot content.

The separate `fleet-status-publisher` has the same dedicated bucket binding and
one `PUBLISH_TOKEN` secret. It has no Cloudflare administration credential.
Its bearer authorizes only `PUT/HEAD /v1/status.json`; it cannot publish a
second key, list/read object contents, delete data, or control infrastructure.
The read-only Worker has no publisher secret or mutation route. R2 bindings
are themselves capable objects; the dedicated dataset and fixed request
handlers define these boundaries.

## NAS sender protocol

Use HTTPS and an `Authorization: Bearer …` header. Never put the token in a URL.

1. `HEAD /v1/status.json`: HTTP404 plus `X-Sequence:-1` before first publication;
   otherwise HTTP200 plus `ETag`, `X-Sequence`, `X-Snapshot-Id`, `Last-Modified`.
2. Send a complete UTF-8 JSON snapshot with `Content-Type: application/json`.
   Initial PUT requires `If-None-Match:*`; replacement requires the exact strong
   `If-Match` ETag from HEAD or the previous successful PUT.
3. A successful PUT returns HTTP200 with the same metadata headers and
   `{accepted:true,sequence:N}`. The sequence must be a safe integer greater
   than the previous committed sequence; it need not be contiguous.
4. Missing conditions return428, malformed conditions400, stale ETag412,
   non-increasing sequence409, invalid shape/public semantics422,
   oversized bodies413. R2 enforces the condition atomically against racing
   writers. A failed conditional commit never replaces the object.
5. After a lost PUT response, HEAD reconciles it: matching snapshot ID and
   sequence prove acceptance. A higher remote sequence is a floor for the next
   collection; never overwrite it with an older pending body.

The sender's retained state, scoped token and upload retries belong to the NAS
observer integration. Normal publication does not run Wrangler or carry a
broad Cloudflare token. Publisher errors and logs contain fixed codes, never
raw exceptions, headers or submitted payloads. Authentication hashes both
presented and expected bearer values before Workers Web Crypto's constant-time
comparison.

## Public contract

`contracts/snapshot.schema.json` is copied unchanged from the accepted
10November Valet investigation. `contracts/public-contract.json` is the
producer's reviewed source/key and finite-domain whitelist. Keep it in sync
with the sibling observer contract. Ajv2020 compiles the schema to standalone
code before packaging; no runtime code generation is used in Workers.

Beyond the JSON shape, validation enforces `synthetic:false`, fixed publisher,
sequence/snapshot identity, opaque catalogue/event IDs, selected public subject
IDs and exact labels, registered foreign keys, unique records, known source/key
pairs, primitive value domains, numeric units, source/error scopes, fixed event
summaries and timestamp ordering. Arbitrary strings, raw messages, titles,
paths, account identities and unknown URLs have no pass-through field. Current
subject public URLs are not enrolled. Unknown or uninstrumented values remain
null. The body is capped at1MiB while streaming, independently of Content-Length.

## Build, runtime checks and deploy

Use the project-local pinned tools:

```sh
npm ci --ignore-scripts
npm run check
runtime-test -- npm test
npm run dry-run
```

Run dependency installation, compilation and runtime tests on compute through
`fleet-exec`, staging this nonsecret source directory there first. Invoke
`runtime-test` on that host as well. Keep deployment credentials on NAS.
Wrangler-generated binding/runtime declarations and the standalone validator
are in ignored `.generated/`; regenerate them rather than hand-editing Env.
The package lock pins all tooling. The initial installed Wrangler4.93.0 could
only run a May engine. This new project deliberately pins Wrangler4.162.0 and
its matching Miniflare5.20261113.0-beta, leaving fleet-installed tools alone.
Runtime tests and production configs both request the15November compatibility
date; the upgraded engine accepts it. Remote smoke checks still verify the
actual resource bindings and deployment.

`npm run dry-run` creates credential-free bundles in `dist/reader/` and
`dist/publisher/` at the production compatibility date. This checks packaging,
not production resources. A NAS deployment can use those prebuilt bundles as
entrypoints with `--no-bundle`, retaining each source config and the reader's
`public/` assets directory. The bucket is `fleet-status-public`; reader target
is the custom domain `status.mecattaf.dev`, publisher is a separate workers.dev
Worker. Logs and traces are explicitly enabled in both configs. Root handles
resource creation, secret installation, deployment and live sender proof.

Actual workerd tests cover uninitialized/HEAD behavior, route/method checks
before storage, safe storage failure, fixed-key bearer authentication, required
conditions, synthetic/private/unknown/type/foreign-key/time rejection, partial
stream byte caps, trusted heartbeat versus old source clocks, stale retained
results, conflicting sequences, simultaneous conditional writers, catalogue
identity and static asset headers. They use actual emulated R2, not a JavaScript
mock of conditional writes. A test-only throwing binding checks error handling.

References: [R2 conditional operations](https://developers.cloudflare.com/r2/api/workers/workers-api-reference/#conditional-operations),
[Workers Web Crypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/#timingsafeequal),
[Wrangler configuration](https://developers.cloudflare.com/workers/wrangler/configuration/).
