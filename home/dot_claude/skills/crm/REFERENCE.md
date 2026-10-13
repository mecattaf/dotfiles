# crm API reference

Generated from openapi.json (API version 0.1.0) by `pnpm gen:reference`. Do not edit by hand.

| operationId | method path | scope | exit codes |
|---|---|---|---|
| `attachments.archive` | `POST /v1/attachments/{ref}/archive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `attachments.content` | `GET /v1/attachments/{ref}/content` | R | 0, 1, 2, 3, 5, 6 |
| `attachments.create` | `POST /v1/attachments` | W | 0, 1, 2, 3, 4, 5, 6 |
| `attachments.get` | `GET /v1/attachments/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `attachments.list` | `GET /v1/attachments` | R | 0, 1, 2, 3, 5, 6 |
| `batch.run` | `POST /v1/batch` | W | 0, 1, 2, 3, 4, 5, 6 |
| `board` | `GET /v1/board/{pipeline}` | R | 0, 1, 2, 3, 5, 6 |
| `calls.assign` | `POST /v1/calls/{ref}/assign` | W | 0, 1, 2, 3, 4, 5, 6 |
| `calls.unmatched` | `GET /v1/calls/unmatched` | R | 0, 1, 5, 6 |
| `contacts.archive` | `POST /v1/contacts/{ref}/archive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.assert` | `PUT /v1/contacts` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.create` | `POST /v1/contacts` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.delete` | `DELETE /v1/contacts/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.emails.add` | `POST /v1/contacts/{ref}/emails` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.emails.list` | `GET /v1/contacts/{ref}/emails` | R | 0, 1, 2, 3, 5, 6 |
| `contacts.emails.primary` | `POST /v1/contacts/{ref}/emails/{email}/primary` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.emails.remove` | `DELETE /v1/contacts/{ref}/emails/{email}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.get` | `GET /v1/contacts/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `contacts.links.add` | `POST /v1/contacts/{ref}/links` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.links.remove` | `DELETE /v1/contacts/{ref}/links/{related}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.list` | `GET /v1/contacts` | R | 0, 1, 2, 3, 5, 6 |
| `contacts.merge` | `POST /v1/contacts/{winner}/merge/{loser}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.patch` | `PATCH /v1/contacts/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `contacts.unarchive` | `POST /v1/contacts/{ref}/unarchive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `context` | `GET /v1/context/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `deals.archive` | `POST /v1/deals/{ref}/archive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.assert` | `PUT /v1/deals` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.create` | `POST /v1/deals` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.delete` | `DELETE /v1/deals/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.get` | `GET /v1/deals/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `deals.list` | `GET /v1/deals` | R | 0, 1, 2, 3, 5, 6 |
| `deals.lose` | `POST /v1/deals/{ref}/lose` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.move` | `POST /v1/deals/{ref}/move` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.patch` | `PATCH /v1/deals/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.people.add` | `POST /v1/deals/{ref}/people` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.people.remove` | `DELETE /v1/deals/{ref}/people/{contact}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.reopen` | `POST /v1/deals/{ref}/reopen` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.unarchive` | `POST /v1/deals/{ref}/unarchive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `deals.win` | `POST /v1/deals/{ref}/win` | W | 0, 1, 2, 3, 4, 5, 6 |
| `dupes` | `GET /v1/dupes` | R | 0, 1, 5, 6 |
| `dupes.verdicts.clear` | `DELETE /v1/dupes/verdicts/{entity}/{left}/{right}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `dupes.verdicts.list` | `GET /v1/dupes/verdicts` | R | 0, 1, 5, 6 |
| `dupes.verdicts.set` | `POST /v1/dupes/verdicts` | W | 0, 1, 2, 3, 4, 5, 6 |
| `email.links.pin` | `POST /v1/email/links` | W | 0, 1, 2, 3, 4, 5, 6 |
| `email.links.unpin` | `DELETE /v1/email/links/{id}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `email.send` | `POST /v1/email/send` | W | 0, 1, 2, 3, 4, 5, 6 |
| `email.sends.get` | `GET /v1/email/sends/{id}` | R | 0, 1, 2, 5, 6 |
| `email.sends.list` | `GET /v1/email/sends` | R | 0, 1, 2, 3, 5, 6 |
| `email.threads.get` | `GET /v1/email/threads/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `email.threads.ingest` | `PUT /v1/email/threads` | W | 0, 1, 4, 5, 6 |
| `email.threads.list` | `GET /v1/email/threads` | R | 0, 1, 2, 3, 5, 6 |
| `email.unmatched` | `GET /v1/email/unmatched` | R | 0, 1, 5, 6 |
| `events` | `GET /v1/events` | R | 0, 1, 5, 6 |
| `export.all` | `GET /v1/export/all` | R | 0, 1, 5, 6 |
| `export.entity` | `GET /v1/export/{entity}` | R | 0, 1, 5, 6 |
| `export.snapshot` | `POST /v1/export/all/snapshot` | W | 0, 1, 4, 5, 6 |
| `find` | `GET /v1/find` | R | 0, 1, 5, 6 |
| `followups.archive` | `POST /v1/follow-ups/{ref}/archive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `followups.assert` | `PUT /v1/follow-ups` | W | 0, 1, 2, 3, 4, 5, 6 |
| `followups.create` | `POST /v1/follow-ups` | W | 0, 1, 2, 3, 4, 5, 6 |
| `followups.delete` | `DELETE /v1/follow-ups/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `followups.done` | `POST /v1/follow-ups/{ref}/done` | W | 0, 1, 2, 3, 4, 5, 6 |
| `followups.drop` | `POST /v1/follow-ups/{ref}/drop` | W | 0, 1, 2, 3, 4, 5, 6 |
| `followups.get` | `GET /v1/follow-ups/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `followups.list` | `GET /v1/follow-ups` | R | 0, 1, 2, 3, 5, 6 |
| `followups.patch` | `PATCH /v1/follow-ups/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `followups.reopen` | `POST /v1/follow-ups/{ref}/reopen` | W | 0, 1, 2, 3, 4, 5, 6 |
| `followups.unarchive` | `POST /v1/follow-ups/{ref}/unarchive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `health` | `GET /health` | open | 0, 1, 5 |
| `history` | `GET /v1/history/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `identities.resolve` | `POST /v1/identities/resolve` | R | 0, 1, 4, 5, 6 |
| `import.contacts` | `POST /v1/import/contacts` | W | 0, 1, 2, 3, 4, 5, 6 |
| `import.interactions` | `POST /v1/import/interactions` | W | 0, 1, 2, 3, 4, 5, 6 |
| `import.orgs` | `POST /v1/import/orgs` | W | 0, 1, 2, 3, 4, 5, 6 |
| `imports.abort` | `POST /v1/import-sessions/{id}/abort` | W | 0, 1, 2, 4, 5, 6 |
| `imports.begin` | `POST /v1/import-sessions` | W | 0, 1, 4, 5, 6 |
| `imports.chunk` | `POST /v1/import-sessions/{id}/chunks` | W | 0, 1, 2, 4, 5, 6 |
| `imports.commit` | `POST /v1/import-sessions/{id}/commit` | W | 0, 1, 2, 4, 5, 6 |
| `imports.get` | `GET /v1/imports/{id}` | R | 0, 1, 2, 5, 6 |
| `imports.list` | `GET /v1/imports` | R | 0, 1, 5, 6 |
| `imports.session` | `GET /v1/import-sessions/{id}` | R | 0, 1, 2, 5, 6 |
| `interactions.archive` | `POST /v1/interactions/{ref}/archive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `interactions.assert` | `PUT /v1/interactions` | W | 0, 1, 2, 3, 4, 5, 6 |
| `interactions.create` | `POST /v1/interactions` | W | 0, 1, 2, 3, 4, 5, 6 |
| `interactions.delete` | `DELETE /v1/interactions/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `interactions.get` | `GET /v1/interactions/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `interactions.list` | `GET /v1/interactions` | R | 0, 1, 2, 3, 5, 6 |
| `interactions.patch` | `PATCH /v1/interactions/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `interactions.unarchive` | `POST /v1/interactions/{ref}/unarchive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `meta.openapi` | `GET /v1/openapi.json` | R | 0, 1, 5, 6 |
| `meta.schema` | `GET /v1/schema` | R | 0, 1, 5, 6 |
| `meta.whoami` | `GET /v1/whoami` | R | 0, 1, 5, 6 |
| `orgs.archive` | `POST /v1/orgs/{ref}/archive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `orgs.assert` | `PUT /v1/orgs` | W | 0, 1, 2, 3, 4, 5, 6 |
| `orgs.create` | `POST /v1/orgs` | W | 0, 1, 2, 3, 4, 5, 6 |
| `orgs.delete` | `DELETE /v1/orgs/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `orgs.domains.add` | `POST /v1/orgs/{ref}/domains` | W | 0, 1, 2, 3, 4, 5, 6 |
| `orgs.domains.list` | `GET /v1/orgs/{ref}/domains` | R | 0, 1, 2, 3, 5, 6 |
| `orgs.domains.remove` | `DELETE /v1/orgs/{ref}/domains/{domain}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `orgs.get` | `GET /v1/orgs/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `orgs.list` | `GET /v1/orgs` | R | 0, 1, 2, 3, 5, 6 |
| `orgs.merge` | `POST /v1/orgs/{winner}/merge/{loser}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `orgs.patch` | `PATCH /v1/orgs/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `orgs.unarchive` | `POST /v1/orgs/{ref}/unarchive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `pipelines.archive` | `POST /v1/pipelines/{ref}/archive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `pipelines.assert` | `PUT /v1/pipelines` | W | 0, 1, 2, 3, 4, 5, 6 |
| `pipelines.create` | `POST /v1/pipelines` | W | 0, 1, 2, 3, 4, 5, 6 |
| `pipelines.delete` | `DELETE /v1/pipelines/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `pipelines.get` | `GET /v1/pipelines/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `pipelines.list` | `GET /v1/pipelines` | R | 0, 1, 5, 6 |
| `pipelines.patch` | `PATCH /v1/pipelines/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `pipelines.unarchive` | `POST /v1/pipelines/{ref}/unarchive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `show` | `GET /v1/show/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `sql.query` | `POST /v1/sql` | R | 0, 1, 4, 5, 6 |
| `stages.archive` | `POST /v1/stages/{ref}/archive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `stages.create` | `POST /v1/pipelines/{ref}/stages` | W | 0, 1, 2, 3, 4, 5, 6 |
| `stages.delete` | `DELETE /v1/stages/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `stages.patch` | `PATCH /v1/stages/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `stages.reorder` | `POST /v1/pipelines/{ref}/stages/reorder` | W | 0, 1, 2, 3, 4, 5, 6 |
| `stages.unarchive` | `POST /v1/stages/{ref}/unarchive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `stale` | `GET /v1/stale` | R | 0, 1, 5, 6 |
| `status` | `GET /v1/status` | R | 0, 1, 5, 6 |
| `tags.archive` | `POST /v1/tags/{ref}/archive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `tags.create` | `POST /v1/tags` | W | 0, 1, 2, 3, 4, 5, 6 |
| `tags.delete` | `DELETE /v1/tags/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `tags.get` | `GET /v1/tags/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `tags.list` | `GET /v1/tags` | R | 0, 1, 5, 6 |
| `tags.members.add` | `POST /v1/tags/{ref}/members` | W | 0, 1, 2, 3, 4, 5, 6 |
| `tags.members.remove` | `DELETE /v1/tags/{ref}/members/{member}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `tags.patch` | `PATCH /v1/tags/{ref}` | W | 0, 1, 2, 3, 4, 5, 6 |
| `tags.unarchive` | `POST /v1/tags/{ref}/unarchive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `timeline` | `GET /v1/timeline/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `today` | `GET /v1/today` | R | 0, 1, 5, 6 |
| `transcripts.archive` | `POST /v1/transcripts/{ref}/archive` | W | 0, 1, 2, 3, 4, 5, 6 |
| `transcripts.attach` | `POST /v1/interactions/{ref}/transcript` | W | 0, 1, 2, 3, 4, 5, 6 |
| `transcripts.content` | `GET /v1/transcripts/{ref}/content` | R | 0, 1, 2, 3, 5, 6 |
| `transcripts.get` | `GET /v1/transcripts/{ref}` | R | 0, 1, 2, 3, 5, 6 |
| `transcripts.index` | `POST /v1/transcripts/{ref}/index` | W | 0, 1, 2, 3, 4, 5, 6 |
| `transcripts.list` | `GET /v1/transcripts` | R | 0, 1, 2, 3, 5, 6 |
| `transcripts.segments` | `GET /v1/transcripts/{ref}/segments` | R | 0, 1, 2, 3, 5, 6 |

## attachments.archive

`POST /v1/attachments/{ref}/archive`: Archive an attachment (the R2 object is kept)

Archives the attachment: it leaves attachments.list and the attachments of its record, stays readable by attachments.get and attachments.content, and its R2 object is kept as evidence of record. The same bytes may then be attached again. Archiving an archived attachment answers 409 state_conflict (exit 4). There is no unarchive. Every attachment route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | an attachment ref (a4) or its bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The archived attachment | AttachmentEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served; storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## attachments.content

`GET /v1/attachments/{ref}/content`: Stream an attachment's bytes

Streams the R2 object of the attachment (live or archived: archive keeps the object) with its stored Content-Type, Content-Length, ETag "<sha256>" and Content-Disposition attachment with the stored filename. A row whose R2 object is missing answers 404 not_found (uploading the same file to the same target again restores the object). Every attachment route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files).

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | an attachment ref (a4) or its bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on a single record |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The file's bytes |  |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## attachments.create

`POST /v1/attachments`: Attach a file to an org, contact, deal or interaction

Takes a multipart/form-data body: file (required; the part's filename and Content-Type are kept), ref (required: the org, contact, deal or interaction, o4, c12, d3, i43 or any resolver input), note (at most 2000 characters) and source (at most 200). The bytes go to R2 under attachments/<sha256> (content-addressed), then the row and its journal (create on the attachment, attach on the target) are written in one batch. A file over MAX_UPLOAD_BYTES (GET /v1/schema limits.max_upload_bytes) answers 413 payload_too_large before anything is stored. The same bytes already live on the same target answer 200 with outcome unchanged and the existing attachment (a safe retry, even without an Idempotency-Key; a missing R2 object is restored); the same bytes live on another target answer 409 uniqueness_conflict naming that attachment in candidates (archive it first). An archived target answers 409 state_conflict. A request that failed after the bytes reached R2 leaves an orphan object until the same upload is retried. Answers 201 with outcome created. Every attachment route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The attachment these bytes already are on this target (outcome unchanged) | AttachmentWriteEnvelope |
| 201 | The created attachment | AttachmentWriteEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed; payload_too_large (exit 1): body over the route's cap | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served; storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## attachments.get

`GET /v1/attachments/{ref}`: Read one attachment's metadata

Returns the attachment (live or archived) as AttachmentMeta. Its bytes are served by GET /v1/attachments/{ref}/content. Every attachment route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files). Errors: 404 not_found or wrong_prefix (exit 2).

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | an attachment ref (a4) or its bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on a single record |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The attachment | AttachmentEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## attachments.list

`GET /v1/attachments`: List live attachments, optionally of one record

Lists live attachments (AttachmentMeta: ref, entity, target, sha256, bytes, content_type, filename, note, source), newest first (sort=-created_at, the default, or created_at; id breaks ties); 50 per page (limit 1 to 200). ref narrows to one org, contact, deal or interaction (any resolver input; archived records are readable). total is exact; next_cursor continues the same route, filter and sort only (else 400 invalid_cursor). Archived attachments are read with attachments.get. Every attachment route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files). Errors: 404 not_found or wrong_prefix, 409 ambiguous_ref for ref; 400 unknown_parameter, validation_error, invalid_cursor.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "created_at" | "-created_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `ref` | query | no | string | resolver input for org or contact or deal or interaction: a prefixed ref (o12, c12, d12, i12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of attachments | AttachmentEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## batch.run

`POST /v1/batch`: Plan and commit ordered mutations atomically

Runs existing entity mutations in order against one natural-key overlay, then one db.batch. Ref fields accept $ops[i].ref for an earlier primary row. Later, self and rowless dependencies answer batch_dependency with op_index. Any planning error refuses all writes and identifies op_index. dry_run projects every result without writes; set it only on this outer request. Operation and D1 budgets are checked before commit.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `BatchIn`

| status | description | body |
|---|---|---|
| 200 | Ordered per-operation results | BatchEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; precondition_failed (exit 1): Go "still holds N" preconditions (pipeline with stages, stage reorder incomplete); blocked_by_references (exit 4): hard delete refused; `error` counts each blocking reference; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; archived_match (exit 4): assert matched only an archived row; `candidates` names it; never silently restored; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## board

`GET /v1/board/{pipeline}`: Open deals grouped by stage

Returns every live stage with exact open and rotting counts and at most per_stage deals (default 50). Each deal includes its next follow-up and stage age. Resolve a pipeline by ref or name; not_found and ambiguous_ref identify resolution failures.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `pipeline` | path | yes | string | pipeline ref or name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `per_stage` | query | no | integer |  |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | Pipeline board | Board |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## calls.assign

`POST /v1/calls/{ref}/assign`: Give an unmatched call its participants, org or deal

Adds the participants in with[] (at least one, at most 50, deduplicated; a participant already on the call is kept, never removed) and sets org or deal when sent (null or "" clears). The call then has a link and leaves GET /v1/calls/unmatched. An archived contact, org or deal answers 409 state_conflict; an unknown ref answers 404 not_found or 409 ambiguous_ref. Assigning the same participants again is a no-op (no journal row). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | an interaction ref (i12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `CallAssign`

| status | description | body |
|---|---|---|
| 200 | The call after the assignment | object |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## calls.unmatched

`GET /v1/calls/unmatched`: List logged calls that have no participants yet

Lists live interactions of kind call with no participant, newest first (occurred_on, id descending), each with ref, occurred_on, summary, external_ref and the ref of its live transcript or null. A recorder logs a call before its participants are known (SPEC.md D9); assign them with POST /v1/calls/{ref}/assign, which removes the call from this list. limit 1 to 200 (default 50); total is exact and the route issues no cursor.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of unmatched calls | UnmatchedCallsEnvelope |
| 400 | Bad request. validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## contacts.archive

`POST /v1/contacts/{ref}/archive`: Archive a contact (soft) with its email addresses

Archives the contact and, in the same batch with the same archived_at, its live addresses (each enqueued for email reconciliation), so its addresses stop resolving. Archiving an archived contact answers 409 state_conflict (exit 4). expect_rev applies. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The archived contact | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.assert

`PUT /v1/contacts`: Create or update a contact by natural key (idempotent)

Asserts a contact: match (default linkedin,email,name_org) is 1 to 3 of linkedin (handle, case-insensitive), email (any address of the body against live addresses) and name_org (normalized name and the same org, org resolved from the org field; no org means no org). No live hit creates it (201, outcome created); one live hit updates only the fields sent (outcome updated) and adds addresses it does not have yet (they become primary only when the contact has none); an identical assert answers 200 unchanged and writes no journal row. Two different live hits answer 409 ambiguous_ref (exit 3) with both; archived-only hits answer 409 archived_match (exit 4), never restored silently. Two concurrent asserts for one new person yield one row. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on an assert |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `match` | query | no | string | comma list of 1 to 3 of linkedin,email,name_org |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `ContactAssert`

| status | description | body |
|---|---|---|
| 200 | The matched contact, updated or unchanged | ContactEnvelope |
| 201 | The created contact | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; context_conflict (exit 1): both `context` and `context_append` in one PATCH; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; archived_match (exit 4): assert matched only an archived row; `candidates` names it; never silently restored; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.create

`POST /v1/contacts`: Create a contact (with its email addresses)

Creates one contact. name is required; org is any org ref (it must be live); email becomes the primary address and emails[] (at most 20, {email, label?, primary?}) adds more; every address is lowercased and written to contact_emails with a reconcile_queue row, and the primary is mirrored in email. phone, linkedin and location are normalized. source, detail and hint start the provenance columns. Answers 201. Errors: 409 uniqueness_conflict (exit 4) when an address is live on another contact, that contact in candidates[0]; 404 or 409 when org does not resolve to one row; 409 state_conflict when the org is archived; 400 validation_error. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `ContactIn`

| status | description | body |
|---|---|---|
| 201 | The created contact | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.delete

`DELETE /v1/contacts/{ref}`: Hard-delete a contact that nothing references

Deletes the contact for good; confirm=1 is required. Refused with 409 blocked_by_references (exit 4) while interactions, deals, deal people rows, contact links (either end), follow-ups, attachments, manual email links or merged contacts reference it, live or archived, each counted: archive instead. Its addresses, taggings and auto email links go with it. Answers 200 with the pre-delete record and deleted true. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `confirm` | query | no | "1" | must be 1: a hard delete is never implied |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The deleted contact as it was | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; blocked_by_references (exit 4): hard delete refused; `error` counts each blocking reference | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.emails.add

`POST /v1/contacts/{ref}/emails`: Add an email address to a contact

Adds {email, label?, primary?}; it becomes primary (and the email mirror) when primary is true or the contact has none. Writes a reconcile_queue row so threads with this address link to the contact. An address the contact already has changes nothing. Errors: 409 uniqueness_conflict (exit 4) naming the contact that holds it live; 400 validation_error for an invalid address. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `EmailAdd`

| status | description | body |
|---|---|---|
| 200 | The contact with its addresses | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.emails.list

`GET /v1/contacts/{ref}/emails`: List the live email addresses of a contact

Lists the contact's live addresses ({email, label, is_primary, source}), oldest first by default (sort created_at or email). Errors: 404 not_found, 409 ambiguous_ref, 400 invalid_cursor.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "created_at" | "-created_at" | "email" | "-email" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The contact's addresses | ContactEmailEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## contacts.emails.primary

`POST /v1/contacts/{ref}/emails/{email}/primary`: Make one of the contact's addresses primary

Makes a live address of the contact its primary and rewrites the contact's email mirror. Already primary changes nothing. Errors: 404 not_found when the contact has no such live address; expect_rev refuses with 409 stale_write. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `email` | path | yes | string |  |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The contact with its new primary | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.emails.remove

`DELETE /v1/contacts/{ref}/emails/{email}`: Remove (archive) an email address of a contact

Archives one live address (kept as history) and writes a reconcile_queue row. Removing the primary promotes the oldest remaining address, or clears the email mirror when none remains. Errors: 404 not_found when the contact has no such live address. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `email` | path | yes | string |  |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The contact with its remaining addresses | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.get

`GET /v1/contacts/{ref}`: Read one contact with links, emails, org, signals, tags and open deals

Returns the contact with its org summary, live email addresses, links (outgoing and incoming, with type and note), tags, relationship signals and the open deals of the contact and of its org. include=signals,emails,tags,links,deals keeps only the named sections. ref accepts c12, 12, any live email address, a LinkedIn handle or a name. A merged contact forwards to its winner and carries merged_from. Errors: 404 not_found or wrong_prefix, 409 ambiguous_ref (exit 3) with candidates.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on a single record |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `include` | query | no | string | comma list of signals, emails, tags, links, deals |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The contact | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## contacts.links.add

`POST /v1/contacts/{ref}/links`: Link this contact to another (directed, typed, with a note)

Adds a directed link {related, type, note?} from this contact to related (for example introduced, reports_to, knows). The same (contact, related, type) twice answers 409 uniqueness_conflict; a link to itself answers 400 validation_error. Answers the contact with its links. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `LinkIn`

| status | description | body |
|---|---|---|
| 200 | The contact with its links | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.links.remove

`DELETE /v1/contacts/{ref}/links/{related}`: Remove the links between two contacts

Removes the links between this contact and related: only links of the given type, or without type every link between the pair in either direction. No such link answers 404 not_found. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `related` | path | yes | string |  |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `type` | query | no | string | remove only links of this type; without it every link between the pair, either direction, is removed |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The contact with its remaining links | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.list

`GET /v1/contacts`: List contacts with filters, keyset paging and optional signals, emails, tags and links

Lists contacts, 50 per page by default (limit 1 to 200), sorted by name, updated_at or created_at (- for descending), id breaking ties. Filters: q (substring of the normalized name), org (any org ref), tag, email (any live address, normalized), linkedin (handle or URL, case-insensitive), touched_before and touched_after (YYYY-MM-DD against the last interaction), cadence_due=1 or 0, has_email=1 or 0, archived=0 (default), 1 or all. include=signals,emails,tags,links adds those sections. total is exact; next_cursor only continues the same route, filters and sort (else 400 invalid_cursor). Errors: 400 unknown_parameter, validation_error; 404 or 409 when the org or tag filter does not resolve to one row; 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "name" | "-name" | "updated_at" | "-updated_at" | "created_at" | "-created_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of signals, emails, tags, links |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `q` | query | no | string |  |
| `org` | query | no | string | resolver input for org: a prefixed ref (o12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `tag` | query | no | string |  |
| `email` | query | no | string |  |
| `linkedin` | query | no | string |  |
| `touched_before` | query | no | string |  |
| `touched_after` | query | no | string |  |
| `cadence_due` | query | no | "0" | "1" | 1 to enable |
| `has_email` | query | no | "0" | "1" | 1 to enable |
| `archived` | query | no | "0" | "1" | "all" | 0 live rows (default), 1 archived only, all both |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of contacts | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## contacts.merge

`POST /v1/contacts/{winner}/merge/{loser}`: Merge a duplicate contact into another (keeps every fact)

Merges loser into winner in one batch: the loser's addresses move to the winner (the loser's primary becomes primary only when the winner has none), empty winner fields take the loser's values, both contexts are kept under a merge marker, provenance and hints are joined without duplicates, interactions, deals, deal people (roles joined), links (a link both hold keeps one row with both notes; links between the pair are dropped), tags, follow-ups, attachments and email links move to the winner, and the loser is archived with merged_into so its refs forward. Self-merge 400; archived or merged side 409 state_conflict. Not reversible. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `winner` | path | yes | string | the contact that survives |
| `loser` | path | yes | string | the duplicate that is folded in |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The winner after the merge | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.patch

`PATCH /v1/contacts/{ref}`: Change the fields of a contact (true PATCH)

Changes only the fields sent; "" or null clears. email replaces the primary address (the old primary is archived; null clears it and leaves other addresses secondary); use the emails routes to add or promote addresses. org null detaches the contact. context and context_append together answer 400 context_conflict. source and detail append to provenance. A value it already holds after normalization is a silent no-op. A value live on another contact answers 409 uniqueness_conflict naming it. expect_rev refuses with 409 stale_write. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `ContactPatch`

| status | description | body |
|---|---|---|
| 200 | The contact after the change | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; context_conflict (exit 1): both `context` and `context_append` in one PATCH; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## contacts.unarchive

`POST /v1/contacts/{ref}/unarchive`: Unarchive a contact and restore its addresses

Restores the contact and exactly the addresses archived with it. 409 uniqueness_conflict naming the holder when one of them is now live on another contact (nothing changes); 409 state_conflict when the contact is live or was merged into another ("merges are not reversible"). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The restored contact | ContactEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## context

`GET /v1/context/{ref}`: Briefing on a contact, org or deal: profile, signals, links, deals, follow-ups, email, transcripts, timeline

One call before talking to someone: the contact (and its org), the org with its team, or the deal, relationship signals (org signals roll up through its live contacts), links (outgoing and incoming, with notes), open deals (of the contact and of its org; for an org, of the org and of its contacts) with stage and days_in_stage, open follow-ups, the last 10 linked non-automated email threads, the last 10 outbound email sends requested for the record, transcript metadata, and the merged timeline newest first (the timeline route's items; default 20, limit 1 to 200, all=1 for the whole timeline; all with limit answers 400 validation_error). format=md answers text/markdown: the Go briefing document (# Name (c12), profile, dossier, organization, links, deals, team, follow-ups, email threads, transcripts, Timeline (N) with N the whole timeline's size). A bare ref resolves as a contact, then as an org. Not paginated: a briefing over RESPONSE_BUDGET_BYTES answers 422 response_too_large (lower limit). Errors: 404 not_found or wrong_prefix (an unsupported entity), 409 ambiguous_ref.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a prefixed ref (c12, o3, d7, ...) or any resolver input; a bare input resolves as a contact, then as an org |
| `limit` | query | no | integer | timeline entries, 1 to 200 (default 20) |
| `all` | query | no | "0" | "1" | 1: the whole timeline (subject to RESPONSE_BUDGET_BYTES); cannot be combined with limit |
| `format` | query | no | "json" | "md" | json (default) or md, the Go briefing document (text/markdown) |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The briefing (application/json), or the Go document with format=md (text/markdown) | Context |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## deals.archive

`POST /v1/deals/{ref}/archive`: Archive a deal (soft)

Archives the deal; archiving an archived deal answers 409 state_conflict. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The archived deal | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.assert

`PUT /v1/deals`: Create or update a deal by title and org (idempotent)

match=title_org (the default and only key): a live deal with the same normalized title and the same org (or no org when none is sent). None: created (201, outcome created) as deals.create. One: the title spelling, contact and people are updated when sent (people are added or their role replaced, never removed); the stage and pipeline are never changed by an assert (move the deal instead; another pipeline answers 409 state_conflict); nothing to do answers 200 outcome unchanged with no journal row. Two live matches answer 409 ambiguous_ref; archived only answers 409 archived_match. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on an assert |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `match` | query | no | "title_org" | title_org (the default and only key) |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `DealIn`

| status | description | body |
|---|---|---|
| 200 | The matched deal, updated or unchanged | DealEnvelope |
| 201 | The created deal | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; archived_match (exit 4): assert matched only an archived row; `candidates` names it; never silently restored; precondition_failed (exit 1): Go "still holds N" preconditions (pipeline with stages, stage reorder incomplete) | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.create

`POST /v1/deals`: Create a deal in a pipeline stage with its people

Creates {title, pipeline, stage?, org?, contact?, people?: [{contact, role?}]} with at least one of org and contact. stage is resolved within the pipeline (ref or name) and defaults to its first live stage; an archived pipeline or stage answers 409 state_conflict. The deal, its opening stage move (from none) and its people are written in one batch. Answers 201 with the deal detail. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `DealIn`

| status | description | body |
|---|---|---|
| 201 | The created deal | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; precondition_failed (exit 1): Go "still holds N" preconditions (pipeline with stages, stage reorder incomplete) | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.delete

`DELETE /v1/deals/{ref}`: Hard-delete a deal nothing references

Deletes the deal for good; confirm=1 is required. Refused with 409 blocked_by_references (exit 4) while interactions, follow-ups, attachments or manual email links reference it, live or archived, each counted: archive instead. Its stage moves, people, taggings and auto email links go with it. Answers 200 with the pre-delete record and deleted true. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `confirm` | query | no | "1" | must be 1: a hard delete is never implied |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The deleted deal as it was | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; blocked_by_references (exit 4): hard delete refused; `error` counts each blocking reference | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.get

`GET /v1/deals/{ref}`: Read one deal: stage, days in stage, rotting, stage moves, people, follow-ups

Returns the deal detail (R6): pipeline and stage names, org and contact, days_in_stage (whole days since the last stage change), rot_days of its stage and rotting (open, rot_days set, days_in_stage above it), every stage move in order with from, to, time and note (the first is the opening move), people with roles, and its live follow-ups. Errors: 404 not_found or wrong_prefix, 409 ambiguous_ref with candidates.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on a single record |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The deal | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## deals.list

`GET /v1/deals`: List deals with filters, rotting view and keyset paging

Lists deals (Deal records with names, days_in_stage, rotting, stage moves and people), sorted by title, updated_at or created_at (default -updated_at), id breaking ties; 50 per page. Filters: pipeline, stage (a stage of that pipeline; stage without pipeline is 400), status (open, won, lost), org, contact (the deal's contact or one of its people), tag, no_next_step=1 (open deals with no open follow-up), archived=0 (default), 1 or all. rotting=1 lists open deals past their stage's rot_days, most overdue first (overdue_days DESC, id), ignoring sort. total is exact; next_cursor continues the same route, filters and sort only. Errors: 400 unknown_parameter, validation_error, invalid_cursor; 404 or 409 when a filter ref does not name one row.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "title" | "-title" | "updated_at" | "-updated_at" | "created_at" | "-created_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `pipeline` | query | no | string | resolver input for pipeline: a prefixed ref (p12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `stage` | query | no | string | resolver input for stage: a prefixed ref (s12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `status` | query | no | "open" | "won" | "lost" |  |
| `rotting` | query | no | "0" | "1" | 1 to enable |
| `org` | query | no | string | resolver input for org: a prefixed ref (o12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `contact` | query | no | string | resolver input for contact: a prefixed ref (c12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `tag` | query | no | string |  |
| `no_next_step` | query | no | "0" | "1" | 1 to enable |
| `archived` | query | no | "0" | "1" | "all" | 0 live rows (default), 1 archived only, all both |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of deals | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## deals.lose

`POST /v1/deals/{ref}/lose`: Mark a deal lost

Sets status lost, outcome_reason to {reason} (null when absent) and closed_at to now. A won or lost deal answers 409 state_conflict (reopen it first). expect_rev applies. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `Close`

| status | description | body |
|---|---|---|
| 200 | The lost deal | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.move

`POST /v1/deals/{ref}/move`: Move a deal to another stage of its pipeline

Takes {stage, note?}; stage is resolved within the deal's pipeline (a stage of another pipeline is 404 not_found). Records a stage move with the note and resets days_in_stage. The current stage answers 409 state_conflict "already in stage X"; an archived stage answers 409 state_conflict. expect_rev applies. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `Move`

| status | description | body |
|---|---|---|
| 200 | The moved deal | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.patch

`PATCH /v1/deals/{ref}`: Change a deal's title, org or contact

Changes {title?, org?, contact?}; org and contact take null or "" to clear, but the deal keeps at least one of them (else 400 validation_error). Never stage or status: use move, win, lose, reopen (a stage or status field is 400). A no-op writes nothing. expect_rev=N answers 409 stale_write. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `DealPatch`

| status | description | body |
|---|---|---|
| 200 | The deal after the change | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.people.add

`POST /v1/deals/{ref}/people`: Add a person (with a role) to a deal

Takes {contact, role?}: adds the contact to the deal's people, or replaces its role when it is already one with another role; the same contact and role again changes nothing. An archived contact answers 409 state_conflict. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `DealPerson`

| status | description | body |
|---|---|---|
| 200 | The deal with its people | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.people.remove

`DELETE /v1/deals/{ref}/people/{contact}`: Remove a person from a deal

Removes the contact from the deal's people; a contact that is not one answers 404 not_found. The deal's own contact field is not changed (PATCH it). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `contact` | path | yes | string | a contact resolver input |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The deal with its remaining people | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.reopen

`POST /v1/deals/{ref}/reopen`: Reopen a won or lost deal

Sets status open and clears closed_at; outcome_reason is kept as the record of the last outcome. An open deal answers 409 state_conflict. expect_rev applies. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The reopened deal | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.unarchive

`POST /v1/deals/{ref}/unarchive`: Unarchive a deal

Restores an archived deal; a live deal answers 409 state_conflict. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The restored deal | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## deals.win

`POST /v1/deals/{ref}/win`: Mark a deal won

Sets status won, outcome_reason to {reason} (null when absent) and closed_at to now. A won or lost deal answers 409 state_conflict (reopen it first). expect_rev applies. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a deal ref (d5), a bare id or its title |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `Close`

| status | description | body |
|---|---|---|
| 200 | The won deal | DealEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## dupes

`GET /v1/dupes`: Blocked weighted duplicate candidates

Scores live contact and org pairs sharing a name token, non-free-mail registrable domain, or LinkedIn handle. Oversized blocks are reported without expansion. CHUNK_ROWS bounds blocks and PAIRS_MAX bounds evaluated pairs; cursor continues inside a block. Each pair is scored once across blocks. Distinct verdicts are skipped; parked pairs require include_parked=1. Default threshold 0.3.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer |  |
| `cursor` | query | no | string |  |
| `sort` | query | no | "block" | the one dupes order: block key, then left id, then right id |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `type` | query | no | "contact" | "org" |  |
| `threshold` | query | no | number | null |  |
| `include_parked` | query | no | "0" | "1" |  |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | Duplicate candidate chunk | object |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## dupes.verdicts.clear

`DELETE /v1/dupes/verdicts/{entity}/{left}/{right}`: Forget a duplicate verdict

Resolves and orders the pair before deleting the verdict. Returns its previous record with deleted true. dry_run writes nothing. Missing pairs answer not_found.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `entity` | path | yes | "contact" | "org" |  |
| `left` | path | yes | string |  |
| `right` | path | yes | string |  |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | Cleared verdict | VerdictEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## dupes.verdicts.list

`GET /v1/dupes/verdicts`: Page duplicate verdicts

Filter by entity and verdict. Keyset order is entity, left id, right id; total is exact. A cursor is bound to those filters.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer |  |
| `cursor` | query | no | string |  |
| `sort` | query | no | "entity" | the one verdict order: entity, left id, right id |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `entity` | query | no | "contact" | "org" |  |
| `verdict` | query | no | "distinct" | "parked" |  |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | Verdicts | VerdictEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## dupes.verdicts.set

`POST /v1/dupes/verdicts`: Remember a distinct or parked pair

Resolves both refs, orders their ids on the server and stores one verdict: inserts it, or updates the stored one; the same verdict and note again is a no-op with no journal row. A verdict stored concurrently answers uniqueness_conflict naming the left record. A self pair is invalid. dry_run projects without writes; normal writes use the atomic journal path and support Idempotency-Key.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `VerdictIn`

| status | description | body |
|---|---|---|
| 200 | Ordered verdict | VerdictEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## email.links.pin

`POST /v1/email/links`: Pin an email thread to a contact, org or deal by hand

Body {thread, ref}: thread an email thread ref (e12), ref a contact, org or deal (any resolver input; $ops[<i>].ref inside a batch). Writes a manual link: a live auto link on the same pair becomes manual; a pair already pinned answers the thread unchanged with no journal row; after an unpin the old row stays archived as a tombstone and a new manual link is added. A thread is eligible for its email interaction while it is not automated, holds a message and keeps a live link to a live contact: the change re-evaluates it in the same batch (asserted, updated, archived or unarchived), and the thread's auto links are re-checked against the current addresses and domains. Answers the thread with its participants and links. expect_rev is the thread's rev. Errors: 409 state_conflict (exit 4) when the thread or the record is archived; 404 not_found, wrong_prefix; 409 ambiguous_ref; 409 stale_write. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `PinIn`

| status | description | body |
|---|---|---|
| 200 | The thread with the pinned link | EmailThreadEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## email.links.unpin

`DELETE /v1/email/links/{id}`: Unpin one email link (auto or manual)

Archives the live link {id} (ThreadLink.id from email.threads.get), auto or manual. The row stays archived with assigned manual: a tombstone, so neither a later push nor reconciliation links the thread to that record again (pin it again by hand to undo). A thread is eligible for its email interaction while it is not automated, holds a message and keeps a live link to a live contact: the change re-evaluates it in the same batch (asserted, updated, archived or unarchived), and the thread's auto links are re-checked against the current addresses and domains. Answers the thread with its remaining links. expect_rev is the thread's rev. Errors: 404 not_found (no such link); 409 state_conflict (exit 4) when it is already unpinned; 409 stale_write. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `id` | path | yes | integer | the link id (ThreadLink.id in email.threads.get) |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The thread without the link | EmailThreadEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## email.send

`POST /v1/email/send`: Send a message through the mail service and track it

Body {to[], from, subject, text?, html?, require_approval?, dry_run?}. Each item of to (1 to 50) is an address, or any resolver input for a contact, org or deal: a contact contributes its primary address as a recipient and stays a link target of the sent thread, an org or a deal is a link target only (neither holds a mailbox). A contact without a primary address is refused 409 no_email (exit 4) with candidates, and so is a send left without any recipient. from is a mail identity (its address or id); an identity mail does not list is refused 422 unknown_identity (exit 1) with the identities mail lists as candidates. require_approval defaults to false when X-CRM-Actor is cli and to true for every other actor; a non-cli actor that sends false is refused 403 approval_required (exit 6), because a machine send waits for `mail outbox approve`. The message itself is mail's: this route never touches SMTP, a mailbox or an identity store. It calls the mail Worker's EmailBinding (POST /v1/send) with X-Email-Owner, X-Email-Caller and X-Email-Actor and an idempotency key derived from the Idempotency-Key (`crm:` plus 32 hex characters of its SHA-256), so a retry of this request never sends twice. A deployment without the MAIL binding answers 503 feature_unavailable (exit 5). One email_sends row and one journal row are written; the answer is {outbox_id, status, identity}, where status is mail's answer as one of pending_approval, queued, sent, failed or cancelled. The scheduled handler (SPEC 3.14) polls mail for the row, and once the thread the sent message joined arrives through email.threads.ingest it pins the requested org and deal refs, records that thread's email interaction with direction out and sets the row sent; context, timeline and show list the sends of a record. A dry run resolves local targets and checks approval policy, defers identity validation until the real send, calls mail never and writes nothing: outbox_id is null and status is dry_run. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `EmailSendIn`

| status | description | body |
|---|---|---|
| 200 | The accepted send | EmailSendEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token; approval_required (exit 6): a machine actor asked for a send that skips approval; only X-CRM-Actor cli may | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; no_email (exit 4): a ref offered as a mail recipient holds no primary address; `candidates` names the record and its addresses; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint; unknown_identity (exit 1): `from` is not an identity the mail service lists; `candidates` lists the identities it does | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served; feature_unavailable (exit 5): the MAIL service binding is absent, so this deployment cannot send | Error |

## email.sends.get

`GET /v1/email/sends/{id}`: One outbound send, with the thread and interaction it reached

Answers one email_sends row by its id or by the mail outbox id the send answered with (o_...). thread is the CRM email thread the sent message joined once mail's push delivered it, and interaction that thread's outbound email interaction; both are null while the send is still on its way. Errors: 404 not_found.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `id` | path | yes | string | the email_sends row id, or the mail outbox id the send answered with |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The send | EmailSendRecordEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## email.sends.list

`GET /v1/email/sends`: List outbound sends and their tracked state

Lists email_sends rows newest first: {id, outbox_id, account, identity, subject, targets, status, sent_message_id, mail_thread_ref, thread, interaction, created_at, updated_at}. status= one of pending_approval, queued, sent, failed, cancelled; account= one mail account label; identity= one identity address; target= a contact, org or deal (any resolver input) the send was requested for (exact: the requested targets, no roll-up). sort created_at, id or status, - for descending, id breaking ties; 50 per page (limit 1 to 200); total is exact; next_cursor continues the same filters and sort only. Errors: 400 unknown_parameter, validation_error, invalid_cursor; 404 not_found or wrong_prefix and 409 ambiguous_ref for target; 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "created_at" | "-created_at" | "id" | "-id" | "status" | "-status" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `status` | query | no | object | one status only |
| `account` | query | no | string | one mail account label |
| `identity` | query | no | string | one identity address |
| `target` | query | no | string | a contact, org or deal ref (any resolver input) the send was requested for |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of sends | EmailSendRecordEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## email.threads.get

`GET /v1/email/threads/{ref}`: One email thread with its participants and links

Answers the thread (archived ones too) with its metadata, its participants (handle, display_name, role, resolved: the live contact holding the address, else the live org holding its domain, else null) and its live links ({id, ref, entity, assigned auto or manual, matched_by}); a link's id is what email.links.unpin takes. The thread's email interaction, when it has one, is interaction. Errors: 404 not_found, wrong_prefix.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | an email thread ref (e12) or its bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The thread | EmailThreadEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## email.threads.ingest

`PUT /v1/email/threads`: Push email thread metadata from the email service

The email service's push (SPEC 3.12, identical to email SPEC 7.8): body {threads: ThreadIn[]} (1 to 100), each {thread_ref (the bare email-service id, never prefixed), account, subject, first_at, last_at, message_count, last_direction, automated, participants: [{handle, display_name, role}]} and nothing else. Over the binding door only X-CRM-Caller email may push, with X-CRM-Actor email:<account> or import:email (403 otherwise); send Idempotency-Key (the payload sha256). Idempotent on (account, thread_ref): fields are overwritten, participants replaced as a set, and auto links reconciled: an address of a live contact links the contact (matched_by contact_email) and the contact's org, an address whose domain a live org owns links the org (org_domain); self addresses never link; manual links and unpinned auto links (manual tombstones) are never touched. A thread that is not automated, holds a message and keeps a live contact link gets one email interaction (external_ref email:thread:<account>:<thread_ref>, dated by last_at, participants the linked contacts); it is updated as the thread moves, archived when the thread stops being eligible and unarchived when it is again. items[i] is the ThreadOut of threads[i]: outcome created, updated or unchanged; stale (last_at older than stored, or equal with fewer messages: nothing applied); emptied (message_count 0 and no participants: participants cleared, auto links and the interaction archived, manual links kept; applied whatever its dates); deferred (the request's D1 budget ran out before this thread, or its thread_ref was already in this push: untouched, send it again); rejected (this thread alone needs more than one request's budget, error {code: platform_limit_exceeded}, or cannot be applied as sent; the rest of the push proceeds). thread is null only for a thread never stored that came back deferred or rejected. warnings holds self_addresses_unset while SELF_ADDRESSES is empty. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `ThreadsIngest`

| status | description | body |
|---|---|---|
| 200 | One ThreadOut per thread, in request order | ThreadOutEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## email.threads.list

`GET /v1/email/threads`: List email threads, filtered by record, domain, account or dates

Lists live email threads as EmailThread records (subject, dates, message count, direction, account, automated, the generated interaction): ref= a contact, org or deal (any resolver input) keeps the threads linked to it, an org's list also holding the threads linked to its live contacts; domain= threads with a participant at that registrable domain or a subdomain (any URL or host form); account= one email account label; after= and before= (YYYY-MM-DD, inclusive, UTC) bound last_at; human_only=1 leaves automated threads out. include=links adds participants (each with the contact or org its address resolves to) and live links. sort last_at (default -last_at), first_at or created_at, - for descending, id breaking ties; 50 per page (limit 1 to 200); total is exact; next_cursor continues the same filters and sort only. Errors: 400 unknown_parameter, validation_error, invalid_cursor; 404 not_found or wrong_prefix and 409 ambiguous_ref for ref; 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "last_at" | "-last_at" | "first_at" | "-first_at" | "created_at" | "-created_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of links |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `ref` | query | no | string | resolver input for contact or org or deal: a prefixed ref (c12, o12, d12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `domain` | query | no | string |  |
| `account` | query | no | string |  |
| `after` | query | no | string |  |
| `before` | query | no | string |  |
| `human_only` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of email threads | EmailThreadEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## email.unmatched

`GET /v1/email/unmatched`: Email addresses seen in human threads that no contact owns yet

Lists every handle that appears in a live, non-automated email thread and is not the address of a live contact, grouped per handle: {handle, display_name (the latest one seen), thread_count, two_way, last_at, domain (registrable), domain_org (the org owning that domain, when one does; never for free-mail)}. Self addresses (SELF_ADDRESSES) and addresses that send automated mail are left out; with SELF_ADDRESSES unset, self never matches and your own address can appear. two_way is true when the address wrote to you and you wrote to it (it is a recipient in a thread you sent or whose last message went out). Ordered two_way first, then thread_count descending, then handle; total is exact. Assert a contact for a row (crm contact assert with the handle as email) to take it off this list. Page size 1 to 200 (default 50); next_cursor continues this list only. Errors: 400 invalid_cursor (restart without cursor), unknown_parameter, validation_error; 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "-two_way" | the one unmatched order: two_way DESC, thread_count DESC, handle ASC |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of unmatched handles | UnmatchedEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## events

`GET /v1/events`: Change feed: journal rows after an id, ascending, with has_more

Delivers journal rows with id greater than after (default 0), ascending, filtered by entity, op and actor (exact). next_cursor is always the id of the last delivered row, or the after value when none came back, so a follower stores it and polls with after=<next_cursor> (cursor=<next_cursor> is the same and wins over after); has_more says whether more rows wait. total is null. Page size 1 to 200 (default 50). This replaces the Go post-write hook. Errors: 400 validation_error, unknown_parameter, invalid_cursor (a cursor that is not a change id); 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `after` | query | no | integer | deliver changes with id greater than this (default 0) |
| `entity` | query | no | string | only changes of this entity (contact, org, deal, interaction, contact_email, ...) |
| `op` | query | no | string | only changes with this op (create, update, archive, merge, move, ...) |
| `actor` | query | no | string | only changes by this actor (exact) |
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | the next_cursor of the previous page (the last delivered change id); same as after, and wins over it |
| `sort` | query | no | "id" | the one events order: id ascending |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | Journal rows after the cursor | ChangeEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## export.all

`GET /v1/export/all`: Export every data table, paged (the backup a restore imports)

Pages through every data table (archived rows and the journal included) in the restore dependency order: orgs, contacts, contact_links, pipelines, stages, deals, stage_moves, interactions, interaction_people, deal_people, contact_emails, org_domains, follow_ups, tags, taggings, transcripts, transcript_segments, attachments, email_threads, email_participants, email_links, dupe_verdicts, imports, changes; rowid order within a table. Each page is {format: crm-export/1, table, rows, rows_sha256, as_of, next_cursor}: rows are the stored columns as D1 holds them, rows_sha256 the sha256 of JSON.stringify(rows), as_of the max(changes.id) the first page recorded. The first page adds manifest {format, migrations, as_of, tables: {<table>: {rows, max_id}}} (imports.begin takes it with chunk_count added); the last page (next_cursor null) adds end_as_of, max(changes.id) now, and consistent = end_as_of equals as_of: false means a mutation ran during the export, so export again from the first page (crm export all retries once, then writes the file with consistent false and exits 5). tables narrows to a comma list of data tables (still in dependency order). limit sets rows per page (1 to 200, default and ceiling CHUNK_ROWS). Control tables are never exported. Pages are exempt from RESPONSE_BUDGET_BYTES. Errors: 400 validation_error (field tables: not a data table), invalid_cursor (from another route or other tables: restart without cursor), unknown_parameter.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | rows per page, 1 to 200; default and ceiling CHUNK_ROWS (GET /v1/schema limits.chunk_rows) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "rowid" | the only order: dependency order of the tables, rowid within a table |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this export |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `tables` | query | no | string | comma list of data tables to export (default: every data table): orgs, contacts, contact_links, pipelines, stages, deals, stage_moves, interactions, interaction_people, dupe_verdicts, contact_emails, org_domains, deal_people, changes, imports, follow_ups, tags, taggings, transcripts, transcript_segments, attachments, email_threads, email_participants, email_links |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | One page of the export | ExportPage |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## export.entity

`GET /v1/export/{entity}`: Export orgs, contacts, interactions or deals as JSON or CSV

Every row of the entity, archived included, by id ascending: ref, every stored column, then the Go derived columns (contacts: links {outgoing, incoming} with each link's type and note; deals: pipeline and stage names, days_in_stage, rot_days; interactions: contact_ids). format=json (default) answers the list envelope with an exact total; format=csv answers RFC 4180 text (CRLF line ends, a header line on every page, NULL as an empty cell, links and contact_ids as JSON cells) with the next page's cursor in the X-Next-Cursor header (absent on the last page) and the total in X-Total-Count. limit 1 to 200 (default 50); a cursor continues the same entity and format only. Errors: 400 validation_error (an entity other than orgs, contacts, interactions, deals), invalid_cursor, unknown_parameter.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `entity` | path | yes | "orgs" | "contacts" | "interactions" | "deals" | orgs, contacts, interactions or deals (export all has its own route) |
| `limit` | query | no | integer | rows per page, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "id" | "-id" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this export |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `format` | query | no | "json" | "csv" | json: the list envelope; csv: RFC 4180 text with a header line on every page |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of the entity | ExportEntityEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## export.snapshot

`POST /v1/export/all/snapshot`: Write the export.all backup to R2 under exports/

Stores the export.all pages in R2 as one backup file, exports/<yyyy>/<mm>/<dd>/export-<as_of>-<id>.json = {format: crm-export/1, as_of, end_as_of, consistent, written_at, pages: [the export.all pages]}, with custom metadata owner_id, sha256 and uploaded_by (the actor). One call stores the pages its D1 budget allows: while status is partial, call again with next_cursor; the call that reaches the last page assembles the file (streamed, sha256 computed on the way), removes the temporary parts and answers status written with key, bytes, sha256, end_as_of and consistent (false: a mutation ran during the snapshot; take another). limit sets rows per page as in export.all. A retried call with the same cursor rewrites the same part, or answers the backup it already wrote. With an Idempotency-Key the key is claimed before anything is written to R2: a repeat of a completed call replays its receipt (Idempotent-Replayed: true), a concurrent duplicate answers 409 idempotency_in_flight, and a call whose request died is re-run under the same object keys when its key is retried after 60 seconds. dry_run=1 names the key the snapshot would write and writes nothing. Used by the nightly backup routine outside this repo. Errors: 503 storage_unavailable (exit 5) when the FILES (R2) binding is absent; 400 invalid_cursor (restart without cursor); 409 import_in_progress while a snapshot import session is open. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | rows per page, 1 to 200; default and ceiling CHUNK_ROWS (GET /v1/schema limits.chunk_rows) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this export |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this export |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The snapshot receipt; next_cursor continues a partial snapshot | ExportSnapshotEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served; storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## find

`GET /v1/find`: Full-text search across contacts, orgs, deals, interactions and transcripts

Searches the FTS5 indexes of contacts, orgs, deals, interactions and transcript segments. q is tokenized on whitespace, each token matched as a quoted phrase and the last one as a prefix (Prob finds Probe); quotes, @, ., - and : are safe. raw=1 passes q to FTS5 unchanged (OR, NEAR, column filters); a malformed raw query answers 400 validation_error with field q. type restricts to one of contact, org, deal, interaction, transcript. Rows are {type, ref, name, detail, rank}: rank is the row's bm25 divided by the best bm25 of its table, in (0, 1] with 1 the best; the contacts of a matched org are added at 0.9 times the org's rank; rows are ordered by rank descending, then contact, org, deal, interaction, transcript, then id. Archived rows are excluded. detail: contact email and org, org category and location, interaction date and kind, deal pipeline and stage, transcript segment speaker and interaction ref. Not paginated: limit 1 to 200 (default 20), next_cursor always null, total null. Over budget the result is narrowed to the largest fitting prefix with warning truncated_to_budget; a single oversized row answers 422 naming its ref. Errors: 400 validation_error (empty q, malformed raw, limit out of range), unknown_parameter; 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `q` | query | yes | string | search text: tokens are matched as quoted phrases, the last one as a prefix (Prob finds Probe); with raw=1 the FTS5 query grammar |
| `type` | query | no | "contact" | "org" | "deal" | "interaction" | "transcript" | restrict to one entity type |
| `raw` | query | no | "0" | "1" | 1: pass q to FTS5 unchanged (OR, NEAR, column filters); a malformed query answers 400 validation_error |
| `limit` | query | no | integer | rows to return, 1 to 200 (default 20); find is not paginated |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect here: rows are ordered by normalized score |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | Matching rows, best first | FindEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## followups.archive

`POST /v1/follow-ups/{ref}/archive`: Archive a follow-up (soft)

Archives the follow-up: it leaves lists, context and signals but keeps its data. Archiving an archived follow-up answers 409 state_conflict (exit 4): it already is. expect_rev applies. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a follow-up ref (f12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The archived follow-up | FollowUpEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## followups.assert

`PUT /v1/follow-ups`: Create or update a follow-up by external_ref (idempotent)

match=external_ref is required and the body must carry external_ref. No live follow-up holds it: created (201). One does: only the fields sent are updated (200, rev increments); an identical assert answers 200 with the record unchanged and writes no journal row. The assert outcome is answered on the envelope as outcome: created, updated or unchanged (the record's own outcome field is the close outcome, so it is not overwritten). Only an archived follow-up holds it: 409 archived_match naming it (never restored silently). A follow-up is about a relationship: it targets at least one of contact, org, deal (work that is not about a relationship belongs in the backlog service; external_ref carries the backlog task id when a commitment lives in both). An archived contact, org, deal or interaction answers 409 state_conflict (unarchive it first). Use it for commitments mirrored from the backlog or a seed. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on an assert |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `match` | query | yes | "external_ref" | required: external_ref |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `FollowUpIn`

| status | description | body |
|---|---|---|
| 200 | The matched follow-up, updated or unchanged | FollowUpAssertEnvelope |
| 201 | The created follow-up | FollowUpAssertEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; archived_match (exit 4): assert matched only an archived row; `candidates` names it; never silently restored | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## followups.create

`POST /v1/follow-ups`: Add a follow-up on a contact, org or deal

Creates an open follow-up: title is required; body, due_on (YYYY-MM-DD or null), contact, org, deal, interaction (the event that produced it, such as the call) and external_ref are optional. A follow-up is about a relationship: it targets at least one of contact, org, deal (work that is not about a relationship belongs in the backlog service; external_ref carries the backlog task id when a commitment lives in both). An archived contact, org, deal or interaction answers 409 state_conflict (unarchive it first). external_ref must carry a namespace prefix (backlog:, call:, seed:, dcal:, ...) and is unique among live follow-ups (409 uniqueness_conflict naming the holder: use PUT /v1/follow-ups?match=external_ref to update it instead). Answers 201. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `FollowUpIn`

| status | description | body |
|---|---|---|
| 201 | The created follow-up | FollowUpEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## followups.delete

`DELETE /v1/follow-ups/{ref}`: Hard-delete a follow-up

Deletes the follow-up for good; confirm=1 is required (else 400 validation_error). Nothing references a follow-up, so nothing blocks it; archive is the reversible alternative. Answers 200 with the pre-delete record and deleted true. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a follow-up ref (f12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `confirm` | query | no | "1" | must be 1: a hard delete is never implied |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The deleted follow-up as it was | FollowUpEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## followups.done

`POST /v1/follow-ups/{ref}/done`: Mark a follow-up done, optionally logging the interaction

Marks an open follow-up done. Body {outcome?, log?: {kind, summary}}: outcome records what happened; log also creates an interaction (kind call, meeting, email, message or note; the summary; dated today in CRM_TZ) on the follow-up's targets (its contact as the participant, its org and deal) in the same batch. done_at is the request time. A follow-up that is already done or dropped answers 409 state_conflict (exit 4): reopen it first; an archived one answers state_conflict too. expect_rev=N answers 409 stale_write with the current record when the row changed. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a follow-up ref (f12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `FollowUpClose`

| status | description | body |
|---|---|---|
| 200 | The done follow-up | FollowUpEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## followups.drop

`POST /v1/follow-ups/{ref}/drop`: Drop a follow-up, optionally logging an interaction

Marks an open follow-up dropped (no longer worth doing). Body {outcome?, log?: {kind, summary}}: outcome records what happened; log also creates an interaction (kind call, meeting, email, message or note; the summary; dated today in CRM_TZ) on the follow-up's targets (its contact as the participant, its org and deal) in the same batch. done_at is the request time. A follow-up that is already done or dropped answers 409 state_conflict (exit 4): reopen it first; an archived one answers state_conflict too. expect_rev=N answers 409 stale_write with the current record when the row changed. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a follow-up ref (f12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `FollowUpClose`

| status | description | body |
|---|---|---|
| 200 | The dropped follow-up | FollowUpEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## followups.get

`GET /v1/follow-ups/{ref}`: Read one follow-up

Returns the follow-up with its status, due date, done_at and outcome, contact, org and deal summaries, the interaction that produced it and its external_ref. ref is f12 or a bare id; archived follow-ups are readable. Errors: 404 not_found or wrong_prefix.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a follow-up ref (f12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on a single record |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The follow-up | FollowUpEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## followups.list

`GET /v1/follow-ups`: List live follow-ups by due window, status, target or interaction

Lists live follow-ups ordered due_on ascending with undated ones last, then id (sort=title, updated_at or created_at, - for descending, orders by that column then id), 50 per page. due=overdue (due before today), today, week (today through today plus 6 days), none (no due date) or all (default), all relative to today in CRM_TZ. status=open (default), done, dropped or all. ref names a contact, org or deal (the follow-ups targeting it); with an org, rollup=1 adds the follow-ups of its live contacts. interaction names the interaction that produced them. total is exact; next_cursor continues the same route, filters and sort only (else 400 invalid_cursor). Errors: 400 unknown_parameter, validation_error; 404 not_found or 409 ambiguous_ref when ref or interaction does not name one row; 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "due_on" | "-due_on" | "title" | "-title" | "updated_at" | "-updated_at" | "created_at" | "-created_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `due` | query | no | "overdue" | "today" | "week" | "none" | "all" |  |
| `status` | query | no | "open" | "done" | "dropped" | "all" |  |
| `ref` | query | no | string | resolver input for contact or org or deal: a prefixed ref (c12, o12, d12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `rollup` | query | no | "0" | "1" | 1 to enable |
| `interaction` | query | no | string | resolver input for interaction: a prefixed ref (i12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of follow-ups | FollowUpEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## followups.patch

`PATCH /v1/follow-ups/{ref}`: Change a follow-up (title, body, due date, targets, external_ref)

Changes only the fields sent: title, body, due_on, contact, org, deal, external_ref. body, due_on and each target take "" or null to clear. The follow-up must keep one of contact, org, deal: a change that would clear the last answers 409 state_conflict (exit 4). A new external_ref live on another follow-up answers 409 uniqueness_conflict. A no-op returns the record unchanged with no journal row. Status changes go through done, drop and reopen. expect_rev=N answers 409 stale_write with the current record when the row changed. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a follow-up ref (f12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `FollowUpPatch`

| status | description | body |
|---|---|---|
| 200 | The follow-up after the change | FollowUpEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## followups.reopen

`POST /v1/follow-ups/{ref}/reopen`: Reopen a done or dropped follow-up

Sets a done or dropped follow-up open again: done_at is cleared, the outcome text is kept. An open follow-up answers 409 state_conflict (exit 4). expect_rev applies. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a follow-up ref (f12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The reopened follow-up | FollowUpEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## followups.unarchive

`POST /v1/follow-ups/{ref}/unarchive`: Unarchive a follow-up

Restores an archived follow-up. A live follow-up answers 409 state_conflict; an external_ref now held by another live follow-up answers 409 uniqueness_conflict naming it. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a follow-up ref (f12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The restored follow-up | FollowUpEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## health

`GET /health`: Liveness, version, commit, applied migrations and deployment features

The only unauthenticated route. Use it to check that the Worker answers, which version and git commit run (`commit` is `unknown` when the deploy did not render one), how many D1 migrations are applied and which features this deployment has (files, access, rate_limit). `auth_misconfigured: true` means the auth doors refuse every request until the operator fixes the secrets or Access settings; it never says which check failed. Takes no query parameters. Errors: 400 `unknown_parameter` (exit 1, `field` names the parameter) means the request carried a query parameter; resend without a query string. 400 `validation_error` (exit 1, `field` `X-Request-Id`) means the request sent an `X-Request-Id` that is not 1 to 200 visible ASCII characters; resend without it or with a shorter one. 500 `internal_error` (exit 5) means the Worker could not read the applied migration count from D1 (or failed otherwise); the `request_id` in the body is in the Worker log.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |

| status | description | body |
|---|---|---|
| 200 | The Worker is up | Health |
| 400 | unknown_parameter (exit 1): a query parameter was sent (field names it; /health takes none); or validation_error (exit 1): the X-Request-Id header is present but not 1 to 200 visible ASCII characters | Error |
| 500 | internal_error (exit 5): the migration count query or another server step failed; the request id is in the Worker log | Error |

## history

`GET /v1/history/{ref}`: Journal rows of one record, oldest first, including the rows of records merged into it

Lists the change journal of the ref ascending by id: creates, one update row per changed field with before and after, archives, moves, links, merges. A contact or org also shows the journal rows of every record merged into it. Any ref prefix is accepted; a deleted record remains reachable by its explicit ref when journal rows exist. A bare ref resolves as a contact, then as an org. Page size 1 to 200 (default 50); total is exact; next_cursor continues the same ref only. Errors: 404 not_found or wrong_prefix, 409 ambiguous_ref, 400 invalid_cursor, 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a prefixed ref (c12, o3, d7, ...) or any resolver input; a bare input resolves as a contact, then as an org |
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "id" | the one history order: id ascending |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of journal rows | ChangeEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## identities.resolve

`POST /v1/identities/resolve`: Resolve email addresses to contacts and orgs

Body {handles: [address, ...]}: 1 to 500 addresses (resolve_max_handles in GET /v1/schema limits), normalized (case, spaces). Answers one item per handle in request order: {handle, match, contact?: {ref, name}, org?: {ref, name}} where match is self (a SELF_ADDRESSES entry; never when SELF_ADDRESSES is unset), contact_email (a live address of a live contact; org is the contact's live org), org_domain (the address's registrable domain belongs to a live org; subdomains count), freemail (a free-mail domain with no contact holding the address) or none. A read: the read-only token may call it; set-wise, at most 12 D1 queries for 500 handles. Errors: 400 validation_error (a handle that is not an address, more than 500).

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `ResolveIn`

| status | description | body |
|---|---|---|
| 200 | One resolution per handle, in request order | ResolveEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## import.contacts

`POST /v1/import/contacts`: Import contacts from a CSV file (Go contract)

Creates or matches contacts, one per CSV line: name (or full_name, or first_name and last_name) is required; email, job_title (title), phone, linkedin, location, context (notes), relationship_hint (hint), org (organization, company: matched by exact name_norm) or org_id, provenance_sources, provenance_details are optional. A line matches a contact by email first, then by name_norm. An org that does not exist answers 404 not_found for its line (`no org "X"; try: crm org add ...`) unless create_missing=1, which creates one stub org per unknown name stamped provenance `auto-created by crm import` (its line entry carries auto_created). The body is the CSV file (Content-Type text/csv), the header on line 1; header names are canonicalized (lowercase, runs of other characters to _), so `Job Title` is job_title. The whole file is one atomic write: without skip_errors the first failing line refuses the file with its error prefixed `line N:` and nothing persists; with skip_errors=1 the failing lines are rejected (listed with their line numbers in `rejects` and `lines`) and the valid lines persist. A match is skipped unless update=1, which patches the columns present (an empty cell clears the field) and appends the source (and the line's provenance column) to provenance_sources. A file over csv_max_rows data lines (GET /v1/schema limits) answers 413 payload_too_large: split it, or use `crm import ... --chunked`. The id, created_at, updated_at and archived_at columns are refused when filled (restore ids and timestamps with a snapshot import). The answer is the Import record: counts per table, rejects, and one entry per line (create, update, skip, reject) with the ref; ref is import:<id>, or null when nothing was written (a second run of the same file skips every line and writes nothing). The same file with the same options, once committed, answers 409 uniqueness_conflict naming the import when it would write again. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `source` | query | yes | string | required provenance source, appended to every row the import creates or updates (Go: --source) |
| `update` | query | no | "0" | "1" | 1: patch matched orgs with the columns present and append provenance (default: skip a match) |
| `skip_errors` | query | no | "0" | "1" | 1: a failing line is rejected (listed with its line number) and the valid lines persist; without it any failing line persists nothing |
| `create_missing` | query | no | "0" | "1" | 1: an unknown org named by a line is created as a stub stamped `auto-created by crm import` (the only sanctioned auto-create) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The Import record with the outcome of every line | ImportEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; archived_match (exit 4): assert matched only an archived row; `candidates` names it; never silently restored; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed; payload_too_large (exit 1): body over the route's cap | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## import.interactions

`POST /v1/import/interactions`: Import interactions from JSON lines, idempotent by external_ref

The body (Content-Type application/x-ndjson) holds one InteractionIn JSON object per line, each with external_ref (blank lines are skipped). Each line is an interactions.assert on external_ref: a new external_ref creates, a changed line updates, an identical one is unchanged, so posting the same file again writes 0 rows (every line reports skip with outcome unchanged). A line without source takes the source query parameter. Lines are numbered from 1; without skip_errors the first failing line refuses the file (`line N: ...`) and nothing persists; with skip_errors=1 failing lines are listed in rejects. At most csv_max_rows lines per request (413 payload_too_large: split the file). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `source` | query | yes | string | required: the source of every line that carries none |
| `skip_errors` | query | no | "0" | "1" | 1: a failing line is rejected (listed with its line number) and the valid lines persist; without it any failing line persists nothing |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The Import record with the outcome of every line | ImportEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; archived_match (exit 4): assert matched only an archived row; `candidates` names it; never silently restored; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed; payload_too_large (exit 1): body over the route's cap | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## import.orgs

`POST /v1/import/orgs`: Import orgs from a CSV file (Go contract)

Creates or matches orgs, one per CSV line: the name column (or organization, company) is required; category, website, linkedin, location, focus, context (notes), relationship_hint (hint), provenance_sources (source), provenance_details (detail) are optional. A line matches a live org by name_norm. source is required (the provenance of every created row). The body is the CSV file (Content-Type text/csv), the header on line 1; header names are canonicalized (lowercase, runs of other characters to _), so `Job Title` is job_title. The whole file is one atomic write: without skip_errors the first failing line refuses the file with its error prefixed `line N:` and nothing persists; with skip_errors=1 the failing lines are rejected (listed with their line numbers in `rejects` and `lines`) and the valid lines persist. A match is skipped unless update=1, which patches the columns present (an empty cell clears the field) and appends the source (and the line's provenance column) to provenance_sources. A file over csv_max_rows data lines (GET /v1/schema limits) answers 413 payload_too_large: split it, or use `crm import ... --chunked`. The id, created_at, updated_at and archived_at columns are refused when filled (restore ids and timestamps with a snapshot import). The answer is the Import record: counts per table, rejects, and one entry per line (create, update, skip, reject) with the ref; ref is import:<id>, or null when nothing was written (a second run of the same file skips every line and writes nothing). The same file with the same options, once committed, answers 409 uniqueness_conflict naming the import when it would write again. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `source` | query | yes | string | required provenance source, appended to every row the import creates or updates (Go: --source) |
| `update` | query | no | "0" | "1" | 1: patch matched orgs with the columns present and append provenance (default: skip a match) |
| `skip_errors` | query | no | "0" | "1" | 1: a failing line is rejected (listed with its line number) and the valid lines persist; without it any failing line persists nothing |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The Import record with the outcome of every line | ImportEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; archived_match (exit 4): assert matched only an archived row; `candidates` names it; never silently restored; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed; payload_too_large (exit 1): body over the route's cap | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## imports.abort

`POST /v1/import-sessions/{id}/abort`: Abort a snapshot import session

Deletes exactly the id ranges the chunk receipts recorded, children before parents, and marks the session aborted, which releases the write lock; nothing else is touched (no other row could be written while it was open). Allowed at any time on an open session; a committed or aborted one answers 409 state_conflict. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `id` | path | yes | string | a session id (7) or ref (import-session:7) |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The aborted session | ImportSessionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; precondition_failed (exit 1): Go "still holds N" preconditions (pipeline with stages, stage reorder incomplete); concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed; payload_too_large (exit 1): body over the route's cap | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## imports.begin

`POST /v1/import-sessions`: Open a snapshot import session (restore into an empty book)

Body {source, sha256, manifest: {format: crm-export/1, migrations, tables: {<data table>: {rows, max_id}}, chunk_count}}. Refuses 409 not_empty unless every data table is empty (a restore goes into a fresh deployment), 409 import_in_progress (exit 5) while another session is open, and 409 precondition_failed when the manifest's migration list differs from the applied one. dry_run=1 runs only these checks and opens nothing. While the session is open every other mutating route answers 409 import_in_progress (the binding door too), reads carry the warning import_in_progress and whoami.import_open names it; send the chunks, then commit, or abort. Answers 201 with the ImportSession (ref import-session:<id>, missing lists every seq). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `SessionIn`

| status | description | body |
|---|---|---|
| 200 | dry_run: the session that would open | ImportSessionEnvelope |
| 201 | The opened session | ImportSessionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; not_empty (exit 4): snapshot import into a non-empty database; precondition_failed (exit 1): Go "still holds N" preconditions (pipeline with stages, stage reorder incomplete); uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## imports.chunk

`POST /v1/import-sessions/{id}/chunks`: Send one chunk of a snapshot

Body {seq, sha256, tables: {<data table>: [rows]}}: rows keep their ids and name only their table's columns; tables come in dependency order (orgs, contacts, contact_links, pipelines, stages, deals, stage_moves, interactions, interaction_people, deal_people, contact_emails, org_domains, follow_ups, tags, taggings, transcripts, transcript_segments, attachments, email_threads, email_participants, email_links, dupe_verdicts, imports, changes); at most import_chunk_rows rows (GET /v1/schema limits; 413 payload_too_large). The rows and the chunk's receipt (per table: rows and id range) commit in one batch. A seq already received with the same sha256 answers 200 with outcome unchanged (a safe retry); with another sha256 409 uniqueness_conflict. A row the schema refuses answers 400 validation_error; a row whose parent is not restored yet 409 precondition_failed (send chunks in seq order). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `id` | path | yes | string | a session id (7) or ref (import-session:7) |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `ChunkIn`

| status | description | body |
|---|---|---|
| 200 | The chunk receipt | ImportChunkEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; precondition_failed (exit 1): Go "still holds N" preconditions (pipeline with stages, stage reorder incomplete); concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed; payload_too_large (exit 1): body over the route's cap | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## imports.commit

`POST /v1/import-sessions/{id}/commit`: Commit a snapshot import session (resumable)

Checks that every seq from 0 to chunk_count - 1 arrived and that each data table's row count and max id equal the manifest (409 precondition_failed naming the gap, nothing committed). Then rebuilds the FTS indexes table by table, up to CHUNK_ROWS content rows per request: when they do not all fit, it answers 200 with committed false and commit_progress, and the next call continues. The last call appends one imports row (kind snapshot) and one changes row per restored table (op import), all above the restored ids, and marks the session committed, which releases the write lock. A committed or aborted session answers 409 state_conflict. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `id` | path | yes | string | a session id (7) or ref (import-session:7) |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The session after this call; committed says whether it is done | ImportSessionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; precondition_failed (exit 1): Go "still holds N" preconditions (pipeline with stages, stage reorder incomplete); concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed; payload_too_large (exit 1): body over the route's cap | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## imports.get

`GET /v1/imports/{id}`: Read one import

Returns one imports row: kind, source, sha256, status, counts per table, rejects with line numbers, actor, timestamps. id is 7 or import:7. Errors: 404 not_found.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `id` | path | yes | string | an import id (7) or ref (import:7) |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The import | ImportEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## imports.list

`GET /v1/imports`: List the import history

Lists the imports rows: CSV, interaction, verdict, seed and snapshot imports with their counts per table and rejects, newest first (sort=created_at for oldest first), id breaking ties, 50 per page; total is exact; next_cursor continues the same route and sort only. Errors: 400 unknown_parameter, validation_error, invalid_cursor; 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "created_at" | "-created_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of imports | ImportEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## imports.session

`GET /v1/import-sessions/{id}`: Read a snapshot import session (resume from it)

Returns the session: status (open, committed, aborted), the manifest's migrations and chunk_count, the received seqs and the missing ones (a resume sends only those), per data table the manifest's rows and max_id beside the rows received, and the commit progress (the FTS indexes rebuilt so far). id is 7 or import-session:7. Errors: 404 not_found.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `id` | path | yes | string | a session id (7) or ref (import-session:7) |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The session | ImportSessionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## interactions.archive

`POST /v1/interactions/{ref}/archive`: Archive an interaction (soft)

Archives the interaction: it leaves lists, timelines and signals but keeps its data. Archiving an archived interaction answers 409 state_conflict (exit 4): it already is. expect_rev applies. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | an interaction ref (i12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The archived interaction | InteractionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## interactions.assert

`PUT /v1/interactions`: Create or update an interaction by external_ref (idempotent)

match=external_ref is required and the body must carry external_ref. No live interaction holds it: created (201, outcome created). One does: only the fields sent are updated and with[] adds missing participants (never removes one); an identical assert answers 200 outcome unchanged and writes no journal row. Only an archived interaction holds it: 409 archived_match naming it (never restored silently). Kind call with an external_ref in the call: namespace needs no with, org or deal (SPEC.md ruling D9). occurred_at is RFC3339 with Z or a numeric offset (fractional seconds truncated, stored as UTC seconds with Z; no offset is 400 validation_error); occurred_on is derived from it in the body's tz, else CRM_TZ (23:30Z in September is the next day in Europe/Paris). date alone sets occurred_on and leaves occurred_at null; date with occurred_at must name the same local day (else 400 validation_error, field date). Without either the date is today in tz or CRM_TZ. Use it for calendar events, email threads and imports whose source has a stable id. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on an assert |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `match` | query | yes | "external_ref" | required: external_ref |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `InteractionIn`

| status | description | body |
|---|---|---|
| 200 | The matched interaction, updated or unchanged | InteractionEnvelope |
| 201 | The created interaction | InteractionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; use_transcript_route (exit 1): transcript_path on write; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; archived_match (exit 4): assert matched only an archived row; `candidates` names it; never silently restored | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## interactions.create

`POST /v1/interactions`: Log an interaction (call, meeting, email, message, note) with its participants

Logs one interaction: kind and summary are required, with at least one of with[] (participants, at most 50, deduplicated), org and deal. Exception (SPEC.md ruling D9): kind call with an external_ref in the call: namespace is accepted with no with, org or deal and waits in GET /v1/calls/unmatched until calls.assign gives it participants. occurred_at is RFC3339 with Z or a numeric offset (fractional seconds truncated, stored as UTC seconds with Z; no offset is 400 validation_error); occurred_on is derived from it in the body's tz, else CRM_TZ (23:30Z in September is the next day in Europe/Paris). date alone sets occurred_on and leaves occurred_at null; date with occurred_at must name the same local day (else 400 validation_error, field date). Without either the date is today in tz or CRM_TZ. external_ref must carry a namespace prefix (dcal:, email:thread:, seed:, call:, backlog:, import:) and is unique among live interactions (409 uniqueness_conflict naming the holder: use PUT /v1/interactions?match=external_ref to update it instead). The row and its participants are written in one batch. transcript_path is refused with 400 use_transcript_route: attach the file with POST /v1/interactions/{ref}/transcript. An archived contact, org or deal answers 409 state_conflict (unarchive it first). Answers 201. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `InteractionIn`

| status | description | body |
|---|---|---|
| 201 | The logged interaction | InteractionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; use_transcript_route (exit 1): transcript_path on write; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## interactions.delete

`DELETE /v1/interactions/{ref}`: Hard-delete an interaction that nothing references

Deletes the interaction for good; confirm=1 is required (else 400 validation_error). Refused with 409 blocked_by_references (exit 4) while transcripts (live or archived), attachments, follow-ups (their interaction) or email threads (their email interaction) reference it, each counted: archive instead. Its participant rows go with it. Answers 200 with the pre-delete record and deleted true. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | an interaction ref (i12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `confirm` | query | no | "1" | must be 1: a hard delete is never implied |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The deleted interaction as it was | InteractionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; blocked_by_references (exit 4): hard delete refused; `error` counts each blocking reference | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## interactions.get

`GET /v1/interactions/{ref}`: Read one interaction with participants, org, deal, transcript and attachments

Returns the interaction with its participants (with), org and deal summaries, the metadata of its live transcript (or null), its live attachments and legacy_transcript_path (the notes-relative path of a migrated row, read-only). ref is i12 or a bare id; archived interactions are readable. Errors: 404 not_found or wrong_prefix.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | an interaction ref (i12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on a single record |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The interaction | InteractionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## interactions.list

`GET /v1/interactions`: List interactions newest first with filters and keyset paging

Lists interactions ordered occurred_on, occurred_at, id descending (NULL occurred_at first within a day), 50 per page (limit 1 to 200); sort=occurred_on reverses the order. Filters: with (alias contact: a participant), org (interactions whose org is the org; with rollup=1 also interactions with a participant who works there), deal, kind, after and before (YYYY-MM-DD, inclusive bounds on occurred_on), external_ref (exact), source (exact), archived=0 (default), 1 or all. total is exact; next_cursor continues the same route, filters and sort only (else 400 invalid_cursor). Errors: 400 unknown_parameter, validation_error; 404 not_found or 409 ambiguous_ref when a with, org or deal filter does not name one row; 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "occurred_on" | "-occurred_on" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `with` | query | no | string | resolver input for contact: a prefixed ref (c12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `contact` | query | no | string | resolver input for contact: a prefixed ref (c12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `org` | query | no | string | resolver input for org: a prefixed ref (o12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `rollup` | query | no | "0" | "1" | 1 to enable |
| `deal` | query | no | string | resolver input for deal: a prefixed ref (d12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `kind` | query | no | "call" | "meeting" | "email" | "message" | "note" |  |
| `after` | query | no | string |  |
| `before` | query | no | string |  |
| `external_ref` | query | no | string |  |
| `source` | query | no | string |  |
| `archived` | query | no | "0" | "1" | "all" | 0 live rows (default), 1 archived only, all both |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of interactions | InteractionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## interactions.patch

`PATCH /v1/interactions/{ref}`: Change an interaction (fields, time, participants)

Changes only the fields sent: summary, body, kind, date, occurred_at, tz, duration_s, direction, external_ref, source, org, deal, add_with[], rm_with[]. body and source take "" or null to clear. date alone clears occurred_at; occurred_at recomputes occurred_on; both must agree. The interaction must keep at least one participant, org or deal: a change that would leave none answers 409 state_conflict (exit 4) naming what it would remove. A contact in both add_with and rm_with is 400. A new external_ref live on another interaction answers 409 uniqueness_conflict. A no-op returns the record unchanged with no journal row. expect_rev=N answers 409 stale_write with the current record when the row changed. transcript_path answers 400 use_transcript_route. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | an interaction ref (i12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `InteractionPatch`

| status | description | body |
|---|---|---|
| 200 | The interaction after the change | InteractionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; use_transcript_route (exit 1): transcript_path on write; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## interactions.unarchive

`POST /v1/interactions/{ref}/unarchive`: Unarchive an interaction

Restores an archived interaction. A live interaction answers 409 state_conflict; an external_ref now held by another live interaction answers 409 uniqueness_conflict naming it. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | an interaction ref (i12) or bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The restored interaction | InteractionEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## meta.openapi

`GET /v1/openapi.json`: The OpenAPI 3.1 document of this API

Returns the generated OpenAPI 3.1 document (the committed openapi.json, built from the route registry by `pnpm gen:openapi`). Use it to discover every operation, its parameters, bodies, responses and exit codes. Accepts only the base query parameters of every route (limit, cursor, sort, include, dry_run), which change nothing here; any other parameter is 400 `unknown_parameter`. Errors: 403 `forbidden` (exit 6) for any auth failure; 400 `unknown_parameter`, `validation_error` (a malformed base parameter such as limit=0), `invalid_cursor` (any cursor: this route issues none) or `invalid_actor` (exit 1); 500 `internal_error` (exit 5).

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The OpenAPI document | object |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## meta.schema

`GET /v1/schema`: Entities, fields and editability, enums, ref prefixes, error codes, limits and features

Describes the data model for an agent: every entity with its ref prefix and fields (type, required on create, accepted on create, editable by PATCH, present on the record), the enums, the ref prefixes, every error code with its HTTP status and CLI exit code, the limits of this deployment (`limit` max, D1 query and parameter budget, batch_max_ops, import_chunk_rows, csv_max_rows, resolve_max_handles, chunk rows, response budget, upload cap) and the features. Read it before sizing a batch or an import. Accepts only the base query parameters of every route (limit, cursor, sort, include, dry_run), which change nothing here; any other parameter is 400 `unknown_parameter`. Errors: 403 `forbidden` (exit 6); 400 `unknown_parameter`, `validation_error` (a malformed base parameter such as limit=0), `invalid_cursor` (any cursor: this route issues none) or `invalid_actor` (exit 1); 500 `internal_error` (exit 5).

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The schema report | SchemaReport |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## meta.whoami

`GET /v1/whoami`: Who the server thinks is calling: door, actor, credential, scope and deployment state

Returns the door the request came through (bearer, access, binding), the actor (X-CRM-Actor, default bearer on the public door), the credential name (rw, rw_next, ro, ro_next, a service token common name, or a binding caller; never a secret), the owner id, the scope (rw or ro), the features, whether SELF_ADDRESSES is configured, the open snapshot import session id (or null), whether MAINTENANCE is on, and the time zone. Use it to check a token before writing. Accepts only the base query parameters of every route (limit, cursor, sort, include, dry_run), which change nothing here; any other parameter is 400 `unknown_parameter`. Errors: 403 `forbidden` (exit 6) for any auth failure, uniform, without detail; 400 `unknown_parameter`, `validation_error` (a malformed base parameter such as limit=0), `invalid_cursor` (any cursor: this route issues none) or `invalid_actor` (exit 1); 500 `internal_error` (exit 5).

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The caller as seen by the server | Whoami |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## orgs.archive

`POST /v1/orgs/{ref}/archive`: Archive an org (soft) with its domains

Archives the org and, in the same batch and with the same archived_at, its live domains (each enqueued for email reconciliation); the org leaves live lists and name matches but keeps its data. Archiving an archived org answers 409 state_conflict (exit 4): it already is. expect_rev applies. Does not follow merges. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The archived org | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## orgs.assert

`PUT /v1/orgs`: Create or update an org by natural key (idempotent)

Asserts an org: match (default domain,name) is 1 to 3 of domain (any of the body's domains), name (normalized name) and linkedin (handle, case-insensitive); every given key is evaluated. No live hit creates it (201, outcome created). One live hit updates only the fields sent (outcome updated), adds missing domains and appends source, detail, hint and context_append unless the same text is already there; an identical assert answers 200 outcome unchanged and writes no journal row. Hits on two different live orgs answer 409 ambiguous_ref (exit 3) with both in candidates (merge them). A hit on archived orgs only answers 409 archived_match (exit 4) naming it: it is never restored silently; unarchive it first. Two concurrent asserts for the same new org yield one row (the loser re-plans and answers unchanged or updated). Errors also: 409 uniqueness_conflict, 400 freemail_domain, context_conflict, validation_error. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on an assert |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `match` | query | no | string | comma list of 1 to 3 of domain,name,linkedin |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `OrgAssert`

| status | description | body |
|---|---|---|
| 200 | The matched org, updated or unchanged | OrgEnvelope |
| 201 | The created org | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; freemail_domain (exit 1): free-mail domain offered as an org domain; context_conflict (exit 1): both `context` and `context_append` in one PATCH | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; archived_match (exit 4): assert matched only an archived row; `candidates` names it; never silently restored | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## orgs.create

`POST /v1/orgs`: Create an org (with its domains)

Creates one org. name is required; website, linkedin and location are normalized (https://host/path, bare LinkedIn handle, trimmed); domains[] (at most 20) are reduced to their registrable domain, the first becomes primary, and each writes a reconcile_queue row for email linkage. source, detail and hint start provenance_sources, provenance_details and relationship_hint. Answers 201 with the record. Errors: 409 uniqueness_conflict (exit 4) when a live org already has the normalized name or one of the domains is live on another org, with that org in candidates[0] (use it, or PUT /v1/orgs to assert); 400 freemail_domain when a domain is a free-mail domain (put the address on a contact instead); 400 validation_error naming the field. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `OrgIn`

| status | description | body |
|---|---|---|
| 201 | The created org | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; freemail_domain (exit 1): free-mail domain offered as an org domain | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## orgs.delete

`DELETE /v1/orgs/{ref}`: Hard-delete an org that nothing references

Deletes the org for good; confirm=1 is required (else 400 validation_error). Refused with 409 blocked_by_references (exit 4) while contacts, deals, interactions, follow-ups, manual email links, attachments or merged orgs reference it, live or archived, each counted in the message: archive instead. Its domains, taggings and auto email links are deleted with it. Answers 200 with the pre-delete record and deleted true. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `confirm` | query | no | "1" | must be 1: a hard delete is never implied |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The deleted org as it was | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; blocked_by_references (exit 4): hard delete refused; `error` counts each blocking reference | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## orgs.domains.add

`POST /v1/orgs/{ref}/domains`: Add a domain to an org

Adds {domain, primary?}: any URL or host form is reduced to its registrable domain (www.x.test/a becomes x.test). It becomes primary when primary is true or the org has none. Writes a reconcile_queue row for email linkage. Adding a domain the org already has changes nothing. Errors: 409 uniqueness_conflict (exit 4) naming the org that holds it live; 400 freemail_domain for free-mail domains; 400 validation_error for a value with no registrable domain. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `DomainAdd`

| status | description | body |
|---|---|---|
| 200 | The org with its domains | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; freemail_domain (exit 1): free-mail domain offered as an org domain; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## orgs.domains.list

`GET /v1/orgs/{ref}/domains`: List the live domains of an org

Lists the org's live domains ({domain, is_primary, source}), oldest first by default (sort created_at, domain). Domains identify the org for the resolver and for email linkage. Errors: 404 not_found, 409 ambiguous_ref, 400 invalid_cursor.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "created_at" | "-created_at" | "domain" | "-domain" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The org's domains | OrgDomainEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## orgs.domains.remove

`DELETE /v1/orgs/{ref}/domains/{domain}`: Remove (archive) a domain of an org

Archives one live domain of the org (the row is kept as history) and writes a reconcile_queue row so auto email links are re-evaluated. Removing the primary promotes the oldest remaining domain. Errors: 404 not_found when the org has no such live domain. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `domain` | path | yes | string |  |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The org with its remaining domains | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## orgs.get

`GET /v1/orgs/{ref}`: Read one org with domains, tags, signals and team

Returns the org as a one-record envelope with its live domains, tags, relationship signals (first and last touch rolled up through its live contacts, touches in 90 days, email dates, open follow-ups, cadence_due) and team (its live contacts). include=signals,domains,tags keeps only the named sections (team is always present). ref is any resolver input: o12, 12, a domain in any URL form, a LinkedIn handle, a name. A merged org forwards to its winner and carries merged_from. Errors: 404 not_found (try crm find) or wrong_prefix, 409 ambiguous_ref (exit 3) with candidates.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on a single record |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `include` | query | no | string | comma list of signals, domains, tags |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The org | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## orgs.list

`GET /v1/orgs`: List orgs with filters, keyset paging and optional signals, domains and tags

Lists orgs, 50 per page by default (limit 1 to 200), sorted by name, updated_at or created_at (prefix - for descending), id breaking ties. Filters: q (substring of the normalized name), category (case-insensitive), tag (a tag ref or name), touched_before and touched_after (YYYY-MM-DD, compared with the last interaction date rolled up through the org's live contacts; never-touched orgs match neither), cadence_due=1 (cadence set and due or never touched; 0 for the opposite), archived=0 live (default), 1 archived only, all. include=signals,domains,tags adds those sections. total is exact; next_cursor continues the same route, filters and sort only (else 400 invalid_cursor). A page over RESPONSE_BUDGET_BYTES is cut with a truncated_to_budget warning. Errors: 400 unknown_parameter, validation_error, invalid_cursor; 404 not_found or 409 ambiguous_ref for the tag filter; 422 response_too_large when one org alone is over budget.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "name" | "-name" | "updated_at" | "-updated_at" | "created_at" | "-created_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of signals, domains, tags |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `q` | query | no | string |  |
| `category` | query | no | string |  |
| `tag` | query | no | string |  |
| `touched_before` | query | no | string |  |
| `touched_after` | query | no | string |  |
| `cadence_due` | query | no | "0" | "1" | 1 to enable |
| `archived` | query | no | "0" | "1" | "all" | 0 live rows (default), 1 archived only, all both |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of orgs | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## orgs.merge

`POST /v1/orgs/{winner}/merge/{loser}`: Merge a duplicate org into another (keeps every fact)

Merges loser into winner in one batch: the loser's domains move to the winner (primary only when the winner has none), empty winner fields take the loser's values, both contexts are kept under a "--- merged from o<id> (<name>) on <date> ---" marker, provenance and hints are joined, contacts, interactions, deals, follow-ups, attachments, tags and email links are repointed, and the loser is archived with merged_into set so its refs forward to the winner. Self-merge answers 400 validation_error; an archived or already merged side answers 409 state_conflict (the remedy names the final winner). Not reversible. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `winner` | path | yes | string | the org that survives |
| `loser` | path | yes | string | the duplicate that is folded in |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The winner after the merge | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## orgs.patch

`PATCH /v1/orgs/{ref}`: Change the fields of an org (true PATCH)

Changes only the fields sent; "" or null clears a field to null. context replaces the dossier, context_append adds a paragraph (both together: 400 context_conflict). source and detail append to provenance (never replaced); hint appends to relationship_hint, null clears it. A value equal to the stored one after normalization is a silent no-op: the record comes back unchanged, updated_at untouched, no journal row. One journal row per changed field. expect_rev=N refuses with 409 stale_write (exit 4, current record in current) when the org changed since you read it. Errors: 409 uniqueness_conflict when the new name is live on another org; 404 not_found, 409 ambiguous_ref. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `OrgPatch`

| status | description | body |
|---|---|---|
| 200 | The org after the change | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; context_conflict (exit 1): both `context` and `context_append` in one PATCH; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## orgs.unarchive

`POST /v1/orgs/{ref}/unarchive`: Unarchive an org and restore its domains

Restores the org and exactly the domains archived with it. Refused with 409 uniqueness_conflict naming the holder when its name or one of those domains is now live on another org (nothing changes), and with 409 state_conflict when the org is live or was merged into another (merges are not reversible). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | any resolver input: a prefixed ref (o12, c12), a bare id, an email, a LinkedIn handle, a domain (orgs) or a name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The restored org | OrgEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## pipelines.archive

`POST /v1/pipelines/{ref}/archive`: Archive a pipeline (soft)

Archives the pipeline; its stages and deals keep their data. New deals cannot enter an archived pipeline (409 state_conflict). Archiving an archived pipeline answers 409 state_conflict. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a pipeline ref (p3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The archived pipeline | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## pipelines.assert

`PUT /v1/pipelines`: Create or complete a pipeline by name (idempotent)

match=name is required. No live pipeline has the normalized name: created with the stages in order (201, outcome created). One has: stages it lacks are appended in the given order and rot_days of named stages is updated when sent (outcome updated); existing stages are never reordered, renamed, archived or deleted; nothing to do answers 200 outcome unchanged with no journal row. Only an archived pipeline has it: 409 archived_match naming it (unarchive it first). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on an assert |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on an assert |
| `match` | query | yes | "name" | required: name |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `PipelineIn`

| status | description | body |
|---|---|---|
| 200 | The matched pipeline, updated or unchanged | PipelineEnvelope |
| 201 | The created pipeline | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; archived_match (exit 4): assert matched only an archived row; `candidates` names it; never silently restored | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## pipelines.create

`POST /v1/pipelines`: Create a pipeline and its stages in one batch

Creates {name, stages?: [{name, rot_days?}]} (at most 30 stages, positions 1..n in the given order, rot_days a positive integer or null). The name is unique among live pipelines (409 uniqueness_conflict naming the holder; PUT /v1/pipelines?match=name asserts instead); a stage name listed twice is 400 validation_error. Answers 201 with the pipeline and its stages. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `PipelineIn`

| status | description | body |
|---|---|---|
| 201 | The created pipeline | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## pipelines.delete

`DELETE /v1/pipelines/{ref}`: Hard-delete an empty pipeline

Deletes the pipeline for good; confirm=1 is required. Refused with 409 precondition_failed (exit 1, Go "still holds N stages") while any stage or deal, live or archived, belongs to it, with both counts: delete those first or archive the pipeline. Answers 200 with the pre-delete record and deleted true. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a pipeline ref (p3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `confirm` | query | no | "1" | must be 1: a hard delete is never implied |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The deleted pipeline as it was | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; precondition_failed (exit 1): Go "still holds N" preconditions (pipeline with stages, stage reorder incomplete) | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## pipelines.get

`GET /v1/pipelines/{ref}`: Read one pipeline: stages in order with rot thresholds and open deal counts

Returns the pipeline with its live stages in position order, each with rot_days and the number of open live deals in it. ref is p3, a bare id or the name. Errors: 404 not_found or wrong_prefix, 409 ambiguous_ref with candidates.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a pipeline ref (p3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on a single record |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The pipeline | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## pipelines.list

`GET /v1/pipelines`: List pipelines with their stages

Lists pipelines, each with its live stages in order (rot_days and open deal counts), sorted by position (default), name, updated_at or created_at (- for descending), id breaking ties; 50 per page (limit 1 to 200). archived=0 (default, live), 1 (archived only), all (both). next_cursor continues the same route, filters and sort only (else 400 invalid_cursor). Errors: 400 unknown_parameter, validation_error.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "position" | "-position" | "name" | "-name" | "updated_at" | "-updated_at" | "created_at" | "-created_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `archived` | query | no | "0" | "1" | "all" | 0 live rows (default), 1 archived only, all both |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of pipelines | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## pipelines.patch

`PATCH /v1/pipelines/{ref}`: Rename a pipeline

Renames the pipeline ({name}). A name live on another pipeline answers 409 uniqueness_conflict; the same name is a no-op with no journal row. expect_rev=N answers 409 stale_write when the pipeline changed. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a pipeline ref (p3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `PipelinePatch`

| status | description | body |
|---|---|---|
| 200 | The renamed pipeline | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## pipelines.unarchive

`POST /v1/pipelines/{ref}/unarchive`: Unarchive a pipeline

Restores an archived pipeline; its name live on another pipeline answers 409 uniqueness_conflict, a live pipeline 409 state_conflict. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a pipeline ref (p3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The restored pipeline | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## show

`GET /v1/show/{ref}`: Read any record by ref (polymorphic by prefix)

Returns the one record a ref names, whatever its entity: c contact (with emails, links, tags, signals, open deals), o org (with domains, tags, signals, team), i interaction, d deal, p pipeline, s stage (answered as its pipeline), f follow-up, t tag (with member counts), x transcript metadata, a attachment metadata, e email thread (with participants and links). A contact, org or deal also carries email_sends: the last 10 outbound sends requested for it, each {outbox_id, status, subject, created_at}. A ref without a prefix resolves as a contact, then as an org (dcal compatibility). A merged contact or org forwards to its winner and carries merged_from. An oversized record answers 422 response_too_large naming its ref. Errors: 404 not_found (try crm find) or wrong_prefix, 409 ambiguous_ref (exit 3) with candidates.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a prefixed ref (c12, o3, d7, ...) or any resolver input; a bare input resolves as a contact, then as an org |
| `limit` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The record | ShowEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## sql.query

`POST /v1/sql`: Execute a guarded read-only SQL query

One SELECT or WITH statement with bound parameters. Comments, stacked statements, write keywords, extension loading and PRAGMA escapes are guarded before D1. An unconditional outer limit caps results at 500 rows, then the response byte budget applies. Returns columns, rows, row_count and truncated. Errors: validation_error for refused or invalid SQL, platform_limit_exceeded for too many parameters, response_too_large for a single oversized row.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `object`

| status | description | body |
|---|---|---|
| 200 | Bounded query result | object |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint; response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## stages.archive

`POST /v1/stages/{ref}/archive`: Archive a stage (soft)

Archives the stage: it leaves the pipeline's live stages and cannot receive moves or new deals (409 state_conflict); deals already in it stay. Archiving an archived stage answers 409 state_conflict. Answers the stage's pipeline. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a stage ref (s7) or bare id; a name works when it is unique among live stages |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The stage's pipeline | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## stages.create

`POST /v1/pipelines/{ref}/stages`: Add a stage to a pipeline

Adds {name, rot_days?, after?: stage, first?: true}: appended last by default, first with first: true, or right after the named live stage (after takes a stage ref or a stage name of this pipeline); later live stages shift down by one. The name is unique among the pipeline's live stages (409 uniqueness_conflict naming the holder). An archived pipeline answers 409 state_conflict. Answers 201 with the pipeline and its stages, and names the created stage in stage {ref, name} (on a dry run ref is null and provisional is $ops[<i>]); in batch.run, $ops[<i>].ref of this op names the created stage. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a pipeline ref (p3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `StageIn`

| status | description | body |
|---|---|---|
| 201 | The pipeline with the new stage | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## stages.delete

`DELETE /v1/stages/{ref}`: Hard-delete a stage no deal ever used

Deletes the stage for good; confirm=1 is required. Refused with 409 blocked_by_references (exit 4) while any deal (live or archived) occupies it or any stage move references it, with both counts: archive instead. Answers the pre-delete pipeline (which stays live, so it carries no deleted flag): the removed stage is marked deleted true inside stages[] and named in deleted_stage. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a stage ref (s7) or bare id; a name works when it is unique among live stages |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `confirm` | query | no | "1" | must be 1: a hard delete is never implied |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The pipeline without the deleted stage | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; blocked_by_references (exit 4): hard delete refused; `error` counts each blocking reference | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## stages.patch

`PATCH /v1/stages/{ref}`: Rename a stage or set its rot threshold

Changes {name?, rot_days?}: rot_days is a positive integer, or null to clear it (Go set-rot none: the stage never rots). A name live on another stage of the pipeline answers 409 uniqueness_conflict. A no-op writes nothing. expect_rev=N answers 409 stale_write. Answers the stage's pipeline. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a stage ref (s7) or bare id; a name works when it is unique among live stages |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `StagePatch`

| status | description | body |
|---|---|---|
| 200 | The stage's pipeline after the change | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## stages.reorder

`POST /v1/pipelines/{ref}/stages/reorder`: Reorder a pipeline's stages (the complete list)

Takes {order: [stage, ...]}: every live stage of the pipeline exactly once, as refs or names; positions become 1..n in that order. A partial list answers 409 precondition_failed (exit 1) naming the missing stages; a stage listed twice is 400 validation_error; an archived stage or a stage of another pipeline is refused (precondition_failed or 404 not_found). Answers the pipeline in its new order. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a pipeline ref (p3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `Reorder`

| status | description | body |
|---|---|---|
| 200 | The pipeline in its new order | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; precondition_failed (exit 1): Go "still holds N" preconditions (pipeline with stages, stage reorder incomplete) | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## stages.unarchive

`POST /v1/stages/{ref}/unarchive`: Unarchive a stage

Restores an archived stage at its old position; its name live on another stage of the pipeline answers 409 uniqueness_conflict, a live stage 409 state_conflict. Answers the stage's pipeline. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a stage ref (s7) or bare id; a name works when it is unique among live stages |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The stage's pipeline | PipelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## stale

`GET /v1/stale`: Contacts or orgs due for a touch

Cadence overrides days (default 90). Never-touched rows come first, then days_since_touch descending and id ascending; recent_first=1 reverses both. Org touches roll up through live contacts. Exact total and a filter-bound CTE keyset cursor; 400 invalid_cursor means restart paging with the same filters.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer |  |
| `cursor` | query | no | string |  |
| `sort` | query | no | "-days_since_touch" | the one stale order: days_since_touch DESC (never touched first), id ASC; recent_first=1 reverses both |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect here |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `days` | query | no | integer | null |  |
| `type` | query | no | "contact" | "org" |  |
| `recent_first` | query | no | "0" | "1" |  |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | Due relationships | StaleEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## status

`GET /v1/status`: Book counts and relationship health

Counts live records, never contacted and stale contacts, overdue follow-ups, cadence and rotting deals. usage reports today’s UTC D1 writes against the deployment budget and warns at 80 percent.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | Book health and quota watch | Status |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## tags.archive

`POST /v1/tags/{ref}/archive`: Archive a tag (soft)

Archives the tag: it leaves tags.list and the tags of records, keeps its memberships, refuses new members (409 state_conflict) and frees its name. Archiving an archived tag answers 409 state_conflict (exit 4). expect_rev applies. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a tag ref (t3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The archived tag | TagEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## tags.create

`POST /v1/tags`: Create a tag

Creates {name, note?}. The name (at most 80 characters) is unique among live tags after normalization (case, accents and spacing folded): a name a live tag holds answers 409 uniqueness_conflict naming it; an archived tag's name is free. Apply it with POST /v1/tags/{ref}/members. Answers 201. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `TagIn`

| status | description | body |
|---|---|---|
| 201 | The created tag | TagEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## tags.delete

`DELETE /v1/tags/{ref}`: Hard-delete a tag and its memberships

Deletes the tag for good with every tagging (each journaled as untag on the tagged org, contact or deal); confirm=1 is required (else 400 validation_error). Archive is the reversible alternative. Answers 200 with the pre-delete record and deleted true. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a tag ref (t3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `confirm` | query | no | "1" | must be 1: a hard delete is never implied |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The deleted tag as it was | TagEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## tags.get

`GET /v1/tags/{ref}`: Read one tag with a page of its members

Returns the tag (one record, with counts per entity) whose members field holds one page of its members {ref, entity, name (a deal's title), tagged_at}, ordered by tagged_at (sort=created_at, the default, or -created_at), then tagging order; entity=org, contact or deal keeps one kind. limit (default 50, 1 to 200) and cursor page the members: next_cursor continues them and total counts the members matching the filter. ref is t3, a bare id or the name; archived tags are readable. Errors: 404 not_found or wrong_prefix, 409 ambiguous_ref, 400 invalid_cursor.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a tag ref (t3), a bare id or its name |
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "created_at" | "-created_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `entity` | query | no | "org" | "contact" | "deal" |  |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The tag with one page of members | TagEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## tags.list

`GET /v1/tags`: List live tags with member counts per entity

Lists live tags, each with counts {org, contact, deal} of its members, sorted by name (default), created_at or updated_at (- for descending), id breaking ties; 50 per page (limit 1 to 200). total is exact; next_cursor continues the same route and sort only (else 400 invalid_cursor). To list the orgs, contacts or deals of a tag use tag=<tag> on their lists, or tags.get. Errors: 400 unknown_parameter, validation_error, invalid_cursor.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "name" | "-name" | "created_at" | "-created_at" | "updated_at" | "-updated_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of tags | TagEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## tags.members.add

`POST /v1/tags/{ref}/members`: Apply a tag to orgs, contacts and deals

Takes {refs: [...]}, 1 to tag_members_max (200, GET /v1/schema limits) orgs, contacts or deals: prefixed refs (o4, c12, d3) or any resolver input, resolved set-wise; a bare name matching rows of two kinds answers 409 ambiguous_ref. Memberships that already exist and refs repeated in the list are no-ops (all existing: 200 with no journal row). An archived tag or member answers 409 state_conflict; an unknown ref 404 not_found, an interaction or other kind 404 wrong_prefix; nothing is written then. Each new membership is journaled as tag on the tagged row. Answers the tag with its counts. A list whose rows and journal rows pass the request's D1 budget answers 413 platform_limit_exceeded before anything is written: send fewer refs per request. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a tag ref (t3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `Members`

| status | description | body |
|---|---|---|
| 200 | The tag with its member counts | TagEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## tags.members.remove

`DELETE /v1/tags/{ref}/members/{member}`: Remove a tag from one org, contact or deal

Removes one membership, journaled as untag on the untagged row. member is the org, contact or deal (o4, c12, d3 or any resolver input); one that does not carry the tag answers 404 not_found. Answers the tag with its counts. In batch.run this op has no primary row, so $ops[<i>].ref of it answers batch_dependency. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a tag ref (t3), a bare id or its name |
| `member` | path | yes | string | the tagged org, contact or deal: a prefixed ref or any resolver input |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The tag with its member counts | TagEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## tags.patch

`PATCH /v1/tags/{ref}`: Rename a tag or change its note

Changes {name?, note?}; note takes "" or null to clear. The name (at most 80 characters) is unique among live tags after normalization (case, accents and spacing folded): a name a live tag holds answers 409 uniqueness_conflict naming it; an archived tag's name is free. A no-op returns the record with no journal row. expect_rev=N answers 409 stale_write with the current record when the row changed. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a tag ref (t3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

Body: `TagPatch`

| status | description | body |
|---|---|---|
| 200 | The tag after the change | TagEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## tags.unarchive

`POST /v1/tags/{ref}/unarchive`: Unarchive a tag

Restores an archived tag with its memberships. A live tag answers 409 state_conflict; its name now held by another live tag answers 409 uniqueness_conflict naming it (rename or archive that one first). expect_rev applies. Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a tag ref (t3), a bare id or its name |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `expect_rev` | query | no | integer | refuse with 409 stale_write when the row's rev differs |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The restored tag | TagEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; stale_write (exit 4): `expect_rev` differs from the row's `rev`; `current` carries the row | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served | Error |

## timeline

`GET /v1/timeline/{ref}`: Merged timeline of a contact, org or deal, newest first, paged

Interactions, stage moves (deals), email threads, follow-ups and the outbound sends requested for the record merged newest first; include=changes interleaves the journal rows of the ref. A contact's timeline: its interactions, linked threads and follow-ups; an org's: interactions with the org or with any of its live contacts, threads linked to it or its contacts, follow-ups on it or its contacts; a deal's: its interactions, stage moves, threads and follow-ups. An email thread's generated interaction is not listed separately: the thread item carries it as interaction. Each item is {type, ref, at, source_rank, id, <type>: record}; an email_send item's ref is the mail outbox id and its record is {outbox_id, status, subject, created_at}; order is at DESC, source_rank ASC (interaction 1, stage_move 2, email_thread 3, follow_up 4, change 5, email_send 6), id DESC. Page size 1 to 200 (default 50); total is null; next_cursor continues the same ref, include and filters only (else 400 invalid_cursor). A bare ref resolves as a contact, then as an org. Errors: 404 not_found or wrong_prefix, 409 ambiguous_ref, 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a prefixed ref (c12, o3, d7, ...) or any resolver input; a bare input resolves as a contact, then as an org |
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "-at" | the one timeline order: at DESC, source_rank ASC, id DESC |
| `include` | query | no | string | comma list of changes |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of timeline items | TimelineEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## today

`GET /v1/today`: Local daily relationship agenda

Local date and timezone, counts of overdue and today follow-ups, rotting deals, the top 20 cadence-due contacts, and changes since the previous local midnight.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on this report |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on this report |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on this report (a report writes nothing) |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | Daily agenda | Today |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |

## transcripts.archive

`POST /v1/transcripts/{ref}/archive`: Archive a transcript (the R2 object and the segments are kept)

Archives the transcript: it leaves transcripts.list, its interaction's transcript field and the interaction's record, stays readable by transcripts.get, transcripts.segments and transcripts.content, and its R2 object and segments are kept as evidence of record. The same bytes may then be attached to another interaction. Archiving an archived transcript answers 409 state_conflict (exit 4). There is no unarchive. The interaction keeps being undeletable while the archived transcript references it. Every transcript route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a transcript ref (x4) or its bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The archived transcript | TranscriptEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served; storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## transcripts.attach

`POST /v1/interactions/{ref}/transcript`: Attach a transcript file to an interaction

Takes a multipart/form-data body with one file part, or the raw bytes with a transcript Content-Type (text/markdown, text/plain, application/json, text/vtt, application/x-subrip or application/octet-stream with format=). The format is format= when sent, else the file extension, else the Content-Type; a body whose format stays unknown answers 400 validation_error (field format). The file is parsed per SPEC 3.8 (diarized md or txt, json segments, vtt or srt): a segment over SEGMENT_MAX_CHARS is split, more than TRANSCRIPT_MAX_SEGMENTS segments answer 413 payload_too_large, a body that parses to no segment answers 400 validation_error (field file). The bytes go to R2 under transcripts/<sha256>.<format> (content-addressed), then the row, as many segments as this request's D1 budget allows (GET /v1/schema limits.transcript_segments_per_request) and the journal (create on the transcript, attach on the interaction) are written in one batch; a large transcript returns segments_indexed < segments_total and is finished by POST /v1/transcripts/{ref}/index. A file over MAX_UPLOAD_BYTES answers 413 payload_too_large before anything is stored. The same bytes again on the same interaction answer 200 with outcome unchanged and the existing row (a safe retry, even without an Idempotency-Key; a missing R2 object is restored); the same sha256 live on another interaction answers 409 uniqueness_conflict naming that transcript in candidates (archive it first). An archived or missing interaction answers 409 state_conflict or 404 not_found. source and language are stored on the row. Answers 201 with outcome created. Every transcript route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | the interaction the transcript is attached to: i43 or any resolver input |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `format` | query | no | "md" | "txt" | "json" | "vtt" | "srt" | the transcript format; without it the file extension infers it, then the Content-Type (400 validation_error, field format, when neither does) |
| `source` | query | no | string | where the transcript came from (a recorder, an export); stored on the row |
| `language` | query | no | string | BCP 47 language tag of the call; stored on the row |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The transcript these bytes already are on this interaction (outcome unchanged) | TranscriptWriteEnvelope |
| 201 | The created transcript | TranscriptWriteEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed; payload_too_large (exit 1): body over the route's cap | Error |
| 415 | Unsupported media type. unsupported_media_type (exit 1): wrong content type | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served; storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## transcripts.content

`GET /v1/transcripts/{ref}/content`: Stream a transcript's bytes

Streams the R2 object of the transcript (live or archived: archive keeps the object as evidence of record) with its format's Content-Type (md text/markdown; charset=utf-8, txt text/plain; charset=utf-8, json application/json, vtt text/vtt; charset=utf-8, srt application/x-subrip), Content-Length and ETag "<sha256>". A row whose R2 object is missing answers 404 not_found (the same upload again restores the object). Every transcript route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files).

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a transcript ref (x4) or its bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on a single record |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The transcript's bytes |  |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## transcripts.get

`GET /v1/transcripts/{ref}`: Read one transcript's metadata

Returns the transcript (live or archived) as TranscriptMeta: metadata, speakers, duration_s and the segment counts. Its bytes are served by GET /v1/transcripts/{ref}/content, its segments by GET /v1/transcripts/{ref}/segments. Every transcript route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files). Errors: 404 not_found or wrong_prefix (exit 2).

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a transcript ref (x4) or its bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.5); has no effect on a single record |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `include` | query | no | string | accepted on every route (SPEC 3.5); has no effect on a single record |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | The transcript | TranscriptEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## transcripts.index

`POST /v1/transcripts/{ref}/index`: Continue indexing a transcript's segments

Re-parses the transcript's R2 object and inserts the segments with seq above the highest stored one, within this request's D1 budget; answers the transcript with {segments_indexed, segments_total}. Call it until segments_indexed equals segments_total (crm transcript attach loops). A complete transcript answers 200 with equal counts and writes nothing. An archived transcript answers 409 state_conflict; a row whose R2 object is missing answers 404 not_found (the same upload again restores it). A concurrent index that stored the same seq first answers 409 uniqueness_conflict naming the transcript; calling index again continues. Every transcript route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files). Every mutation accepts dry_run=1 (also with the read-only token): nothing is written, the projected record comes back with dry_run true and planned_changes. Send an Idempotency-Key to make a retry safe.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a transcript ref (x4) or its bare id |
| `limit` | query | no | integer | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `cursor` | query | no | string | accepted on every route (SPEC 3.5), but this route issues no cursors: any value answers 400 invalid_cursor; omit it |
| `sort` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `include` | query | no | string | accepted on every route (SPEC 3.16); has no effect on a mutation |
| `dry_run` | query | no | "0" | "1" | 1 to enable |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |
| `Idempotency-Key` | header | no | string | Optional, 8 to 128 characters of [A-Za-z0-9:._-]; scoped to (key, door, actor). Checked after auth and the read-only scope. A retry with the same key and the same method, path, query (dry_run included), content type and body returns the stored 2xx response with the Idempotent-Replayed: true header and writes nothing again; the same key with a different request answers 422 idempotency_mismatch; while the first request with the key is still executing (up to 60 seconds) it answers 409 idempotency_in_flight (retry later with the same key). Only 2xx outcomes are stored: a 4xx may be corrected and resent with the same key. dry_run=1 never stores a key. |

| status | description | body |
|---|---|---|
| 200 | The transcript after this call | TranscriptEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern; batch_dependency (exit 1): a batch placeholder names a later op, the op itself, or an op without a primary row | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail; read_only (exit 6): mutating route called with the read-only token | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. idempotency_in_flight (exit 5): the same key is still executing; retry later with the same key; ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates`; state_conflict (exit 4): already archived, not archived, already in stage, already won or lost, already open, already done; uniqueness_conflict (exit 4): live unique value held by another row; `candidates[0]` is the owner; concurrent_modification (exit 5): the server's own re-plans kept meeting a changed row; retry; import_in_progress (exit 5): a snapshot import session is open; non-import writes wait | Error |
| 413 | Too large. platform_limit_exceeded (exit 1): the request would pass the D1 query or parameter budget; nothing was executed | Error |
| 422 | Unprocessable. idempotency_mismatch (exit 4): same Idempotency-Key, different fingerprint | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. maintenance (exit 5): MAINTENANCE=true during a restore; reads are still served; storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## transcripts.list

`GET /v1/transcripts`: List live transcripts, optionally of one interaction, contact or org

Lists live transcripts (TranscriptMeta: ref, interaction, sha256, bytes, format, speakers, duration_s, language, source, segments_indexed, segments_total, created_at, archived_at), newest first (sort=-created_at, the default, or created_at; id breaks ties); 50 per page (limit 1 to 200). interaction narrows to one interaction, contact to the transcripts of the interactions a contact took part in, org to the interactions of the org or of its contacts; after and before filter on the interaction's date (occurred_on, inclusive). total is exact; next_cursor continues the same route, filter and sort only (else 400 invalid_cursor). Archived transcripts are read with transcripts.get. Every transcript route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files). Errors: 404 not_found or wrong_prefix, 409 ambiguous_ref for a filter ref; 400 unknown_parameter, validation_error, invalid_cursor; 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `sort` | query | no | "created_at" | "-created_at" | sort key, "-" for descending; id breaks ties |
| `include` | query | no | string | comma list of (none) |
| `dry_run` | query | no | "0" | "1" | 1 or true: accepted on every route (SPEC 3.5); has no effect on a read |
| `interaction` | query | no | string | resolver input for interaction: a prefixed ref (i12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `contact` | query | no | string | resolver input for contact: a prefixed ref (c12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `org` | query | no | string | resolver input for org: a prefixed ref (o12), a bare id, an email, a LinkedIn handle, a domain or a name; ambiguity answers 409 ambiguous_ref with candidates |
| `after` | query | no | string |  |
| `before` | query | no | string |  |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of transcripts | TranscriptEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## transcripts.segments

`GET /v1/transcripts/{ref}/segments`: Read a transcript's parsed segments, paged by seq

The transcript's segments {transcript, seq, speaker, start_ms, end_ms, text} in seq order (ascending; the cursor continues it), 50 per page (limit 1 to 200), total exact. speaker narrows to one speaker (exact name as parsed); q is an FTS5 query within this transcript only (every whitespace token a quoted phrase, the last one a prefix: invoic finds invoice); speaker and q combine. Only the segments stored so far are listed: a transcript with segments_indexed < segments_total is finished by POST /v1/transcripts/{ref}/index first. Every transcript route answers 503 storage_unavailable (exit 5) when this deployment has no FILES (R2) binding (GET /v1/whoami features.files). Errors: 404 not_found or wrong_prefix; 400 unknown_parameter, validation_error, invalid_cursor; 422 response_too_large.

| parameter | in | required | type | description |
|---|---|---|---|---|
| `ref` | path | yes | string | a transcript ref (x4) or its bare id |
| `limit` | query | no | integer | page size, 1 to 200 (default 50) |
| `cursor` | query | no | string | next_cursor from the previous page of the same route, filters and sort; any other value (corrupt, or from another route, filter set or sort) answers 400 invalid_cursor |
| `speaker` | query | no | string | only segments of this speaker (exact name as parsed) |
| `q` | query | no | string | full-text query within this transcript (FTS5 over speaker and text; every token a quoted phrase, the last one a prefix) |
| `dry_run` | query | no | "0" | "1" | accepted on every route (SPEC 3.5); has no effect on a read |
| `X-Request-Id` | header | no | string | Optional caller id for this request: 1 to 200 visible ASCII characters (0x21-0x7E). Echoed unchanged in the X-Request-Id response header and the error body's request_id; generated when absent; a present value outside the bound is refused with 400 validation_error, field X-Request-Id. |
| `X-CRM-Actor` | header | no | string | Who is writing (attribution, not identity): tom, cli, bearer, system, or claude:, codex:, pi:, import:, email: plus 1 to 40 of [a-z0-9._-]. Absent means bearer on the public door; binding callers must send it. A value outside the pattern answers 400 invalid_actor. |

| status | description | body |
|---|---|---|
| 200 | A page of segments | SegmentEnvelope |
| 400 | Bad request. invalid_cursor (exit 1): cursor from another route, sort, or corrupt; validation_error (exit 1): body or query fails the schema; `field` names it; unknown_parameter (exit 1): query parameter not in the route's whitelist; invalid_actor (exit 1): X-CRM-Actor fails the pattern | Error |
| 403 | Refused by the auth doors or the read-only scope. forbidden (exit 6): any auth failure; uniform body, no detail | Error |
| 404 | Not found. not_found (exit 2): no row for the ref; `remedy` gives a find or create command; wrong_prefix (exit 2): ref prefix names another entity for this route | Error |
| 409 | Conflict. ambiguous_ref (exit 3): two or more rows on the first matching resolver rung; `candidates` | Error |
| 422 | Unprocessable. response_too_large (exit 1): response would exceed RESPONSE_BUDGET_BYTES; page or narrow: add limit, cursor, include | Error |
| 500 | Internal error. internal_error (exit 5): unexpected; logged with request_id; never a constraint error (those map to 409) | Error |
| 503 | Unavailable. storage_unavailable (exit 5): FILES (R2) binding absent | Error |

## Schemas

### AttachmentEnvelope

| field | type | required |
|---|---|---|
| `items` | AttachmentMeta[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### AttachmentMeta

| field | type | required |
|---|---|---|
| `ref` | string | null | yes |
| `entity` | "org" | "contact" | "deal" | "interaction" | yes |
| `target` | string | yes |
| `sha256` | string | yes |
| `bytes` | integer | yes |
| `content_type` | string | yes |
| `filename` | string | null | yes |
| `note` | string | null | yes |
| `source` | string | null | yes |
| `created_at` | string | yes |
| `archived_at` | string | null | yes |
| `provisional` | string | no |

### AttachmentUpload

| field | type | required |
|---|---|---|
| `file` | string | yes |
| `ref` | string | yes |
| `note` | string | no |
| `source` | string | no |

### AttachmentWriteEnvelope

| field | type | required |
|---|---|---|
| `items` | AttachmentMeta[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |
| `outcome` | "created" | "updated" | "unchanged" | no |

### Autocreated

| field | type | required |
|---|---|---|
| `entity` | "contact" | "org" | yes |
| `ref` | string | null | yes |
| `value` | string | yes |
| `thread` | string | null | yes |

### BatchEnvelope

| field | type | required |
|---|---|---|
| `items` | BatchItem[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### BatchIn

| field | type | required |
|---|---|---|
| `ops` | object[] | yes |

### BatchItem

| field | type | required |
|---|---|---|
| `op_index` | integer | yes |
| `operationId` | string | yes |
| `status` | integer | yes |
| `body` | object | no |

### Board

| field | type | required |
|---|---|---|
| `pipeline` | object | yes |
| `stages` | object[] | yes |

### CallAssign

| field | type | required |
|---|---|---|
| `with` | string[] | yes |
| `org` | string | null | no |
| `deal` | string | null | no |

### Candidate

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `name` | string | yes |
| `detail` | string | yes |

### Change

| field | type | required |
|---|---|---|
| `id` | integer | yes |
| `at` | string | yes |
| `actor` | string | yes |
| `door` | "bearer" | "access" | "binding" | "system" | yes |
| `batch_id` | string | yes |
| `request_id` | string | null | yes |
| `entity` | string | yes |
| `row_id` | integer | yes |
| `ref` | object | yes |
| `op` | "create" | "update" | "archive" | "unarchive" | "delete" | "merge" | "merged_into" | "link" | "unlink" | "move" | "win" | "lose" | "reopen" | "tag" | "untag" | "attach" | "done" | "drop" | "verdict" | "import" | yes |
| `field` | string | null | yes |
| `before` | object | no |
| `after` | object | no |

### ChangeEnvelope

| field | type | required |
|---|---|---|
| `items` | Change[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### ChunkIn

| field | type | required |
|---|---|---|
| `seq` | integer | yes |
| `sha256` | string | yes |
| `tables` | object | yes |

### Close

| field | type | required |
|---|---|---|
| `reason` | string | no |

### Contact

| field | type | required |
|---|---|---|
| `ref` | string | null | yes |
| `name` | string | yes |
| `org` | OrgSummary | yes |
| `job_title` | string | null | yes |
| `email` | string | null | yes |
| `phone` | string | null | yes |
| `linkedin` | string | null | yes |
| `location` | string | null | yes |
| `context` | string | null | yes |
| `relationship_hint` | string | null | yes |
| `provenance_sources` | string | null | yes |
| `provenance_details` | string | null | yes |
| `cadence_days` | integer | null | yes |
| `owner_id` | string | yes |
| `rev` | integer | yes |
| `created_at` | string | yes |
| `updated_at` | string | yes |
| `archived_at` | string | null | yes |
| `merged_into` | string | null | yes |
| `merged_from` | string | no |
| `emails` | ContactEmail[] | no |
| `links` | object | no |
| `tags` | TagSummary[] | no |
| `signals` | Signals | no |
| `deals` | DealSummary[] | no |
| `outcome` | "created" | "updated" | "unchanged" | no |
| `deleted` | true | no |
| `provisional` | string | no |

### ContactAssert

| field | type | required |
|---|---|---|
| `name` | string | yes |
| `org` | string | null | no |
| `title` | string | null | no |
| `email` | string | null | no |
| `phone` | string | null | no |
| `linkedin` | string | null | no |
| `location` | string | null | no |
| `context` | string | null | no |
| `hint` | string | null | no |
| `source` | string | no |
| `detail` | string | no |
| `cadence_days` | integer | null | no |
| `emails` | EmailAdd[] | no |
| `context_append` | string | no |

### ContactEmail

| field | type | required |
|---|---|---|
| `email` | string | yes |
| `label` | string | null | yes |
| `is_primary` | boolean | yes |
| `source` | string | null | yes |

### ContactEmailEnvelope

| field | type | required |
|---|---|---|
| `items` | ContactEmail[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### ContactEnvelope

| field | type | required |
|---|---|---|
| `items` | Contact[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### ContactIn

| field | type | required |
|---|---|---|
| `name` | string | yes |
| `org` | string | null | no |
| `title` | string | null | no |
| `email` | string | null | no |
| `phone` | string | null | no |
| `linkedin` | string | null | no |
| `location` | string | null | no |
| `context` | string | null | no |
| `hint` | string | null | no |
| `source` | string | no |
| `detail` | string | no |
| `cadence_days` | integer | null | no |
| `emails` | EmailAdd[] | no |

### ContactPatch

| field | type | required |
|---|---|---|
| `name` | string | no |
| `org` | string | null | no |
| `title` | string | null | no |
| `email` | string | null | no |
| `phone` | string | null | no |
| `linkedin` | string | null | no |
| `location` | string | null | no |
| `context` | string | null | no |
| `hint` | string | null | no |
| `source` | string | no |
| `detail` | string | no |
| `cadence_days` | integer | null | no |
| `context_append` | string | no |

### ContactSummary

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `name` | string | yes |

### Context

| field | type | required |
|---|---|---|
| `contact` | object | no |
| `org` | object | no |
| `deal` | object | no |
| `signals` | object | no |
| `links` | object | yes |
| `deals` | DealSummary[] | yes |
| `team` | object[] | no |
| `follow_ups` | FollowUp[] | yes |
| `email_threads` | EmailThread[] | yes |
| `email_sends` | EmailSendSummary[] | yes |
| `transcripts` | TranscriptMeta[] | yes |
| `timeline` | TimelineItem[] | yes |

### Deal

| field | type | required |
|---|---|---|
| `ref` | string | null | yes |
| `title` | string | yes |
| `status` | "open" | "won" | "lost" | yes |
| `outcome_reason` | string | null | yes |
| `closed_at` | string | null | yes |
| `pipeline` | PipelineSummary | yes |
| `stage` | StageSummary | yes |
| `org` | OrgSummary | yes |
| `contact` | object | yes |
| `days_in_stage` | integer | yes |
| `rot_days` | integer | null | yes |
| `rotting` | boolean | yes |
| `stage_moves` | object[] | yes |
| `people` | object[] | yes |
| `follow_ups` | FollowUp[] | no |
| `owner_id` | string | yes |
| `rev` | integer | yes |
| `created_at` | string | yes |
| `updated_at` | string | yes |
| `archived_at` | string | null | yes |
| `outcome` | "created" | "updated" | "unchanged" | no |
| `deleted` | true | no |
| `provisional` | string | no |

### DealEnvelope

| field | type | required |
|---|---|---|
| `items` | Deal[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### DealIn

| field | type | required |
|---|---|---|
| `title` | string | yes |
| `pipeline` | string | yes |
| `stage` | string | no |
| `org` | string | no |
| `contact` | string | no |
| `people` | object[] | no |

### DealPatch

| field | type | required |
|---|---|---|
| `title` | string | no |
| `org` | string | null | no |
| `contact` | string | null | no |

### DealPerson

| field | type | required |
|---|---|---|
| `contact` | string | yes |
| `role` | string | no |

### DealSummary

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `title` | string | yes |
| `status` | "open" | "won" | "lost" | yes |
| `pipeline` | PipelineSummary | yes |
| `stage` | StageSummary | yes |
| `days_in_stage` | integer | yes |
| `rotting` | boolean | yes |

### DealTitleSummary

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `title` | string | yes |

### DomainAdd

| field | type | required |
|---|---|---|
| `domain` | string | yes |
| `primary` | boolean | no |

### DupeEnvelope

| field | type | required |
|---|---|---|
| `items` | DupeRow[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### DupeRow

| field | type | required |
|---|---|---|
| `left` | object | yes |
| `right` | object | yes |
| `score` | number | yes |
| `reasons` | string[] | yes |
| `scorer` | "weighted" | yes |
| `verdict` | "parked" | no |

### EmailAdd

| field | type | required |
|---|---|---|
| `email` | string | yes |
| `label` | string | no |
| `primary` | boolean | no |

### EmailSend

| field | type | required |
|---|---|---|
| `outbox_id` | string | null | yes |
| `status` | object | yes |
| `identity` | string | yes |

### EmailSendEnvelope

| field | type | required |
|---|---|---|
| `items` | EmailSend[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### EmailSendIn

| field | type | required |
|---|---|---|
| `to` | string[] | yes |
| `from` | string | yes |
| `subject` | string | yes |
| `text` | string | no |
| `html` | string | no |
| `require_approval` | boolean | no |
| `dry_run` | boolean | no |

### EmailSendRecord

| field | type | required |
|---|---|---|
| `id` | integer | yes |
| `outbox_id` | string | yes |
| `account` | string | yes |
| `identity` | string | yes |
| `subject` | string | yes |
| `targets` | string[] | yes |
| `status` | SendStatus | yes |
| `sent_message_id` | string | null | yes |
| `mail_thread_ref` | string | null | yes |
| `thread` | string | null | yes |
| `interaction` | string | null | yes |
| `last_error` | string | null | yes |
| `mail_status` | string | null | yes |
| `thread_account` | string | null | yes |
| `created_at` | string | yes |
| `updated_at` | string | yes |

### EmailSendRecordEnvelope

| field | type | required |
|---|---|---|
| `items` | EmailSendRecord[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### EmailSendSummary

| field | type | required |
|---|---|---|
| `outbox_id` | string | yes |
| `status` | SendStatus | yes |
| `subject` | string | yes |
| `created_at` | string | yes |

### EmailThread

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `thread_ref` | string | yes |
| `account` | string | yes |
| `subject` | string | null | yes |
| `first_at` | string | yes |
| `last_at` | string | yes |
| `message_count` | integer | yes |
| `last_direction` | "in" | "out" | null | yes |
| `automated` | boolean | yes |
| `interaction` | string | null | yes |
| `participants` | object[] | no |
| `links` | ThreadLink[] | no |
| `rev` | integer | yes |
| `created_at` | string | yes |
| `updated_at` | string | yes |
| `archived_at` | string | null | yes |

### EmailThreadEnvelope

| field | type | required |
|---|---|---|
| `items` | EmailThread[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### Error

| field | type | required |
|---|---|---|
| `error` | string | yes |
| `code` | string | yes |
| `exit_code` | integer | yes |
| `candidates` | Candidate[] | no |
| `remedy` | string | no |
| `field` | string | no |
| `op_index` | integer | no |
| `current` | object | no |
| `detail` | ErrorDetail | no |
| `request_id` | string | yes |

### ErrorDetail

| field | type | required |
|---|---|---|
| `outbox_id` | string | no |
| `idempotency_key` | string | no |

### ExportEntityEnvelope

| field | type | required |
|---|---|---|
| `items` | ExportRow[] | yes |
| `count` | integer | yes |
| `total` | integer | yes |
| `next_cursor` | string | null | yes |
| `warnings` | "truncated_to_budget" | "self_addresses_unset" | "import_in_progress"[] | yes |
| `dry_run` | boolean | yes |

### ExportManifest

| field | type | required |
|---|---|---|
| `format` | "crm-export/1" | yes |
| `migrations` | string[] | yes |
| `as_of` | integer | yes |
| `tables` | object | yes |

### ExportPage

| field | type | required |
|---|---|---|
| `format` | "crm-export/1" | yes |
| `manifest` | ExportManifest | no |
| `table` | "orgs" | "contacts" | "contact_links" | "pipelines" | "stages" | "deals" | "stage_moves" | "interactions" | "interaction_people" | "dupe_verdicts" | "contact_emails" | "org_domains" | "deal_people" | "changes" | "imports" | "follow_ups" | "tags" | "taggings" | "transcripts" | "transcript_segments" | "attachments" | "email_threads" | "email_participants" | "email_links" | yes |
| `rows` | object[] | yes |
| `rows_sha256` | string | yes |
| `as_of` | integer | yes |
| `next_cursor` | string | null | yes |
| `end_as_of` | integer | no |
| `consistent` | boolean | no |
| `warnings` | "truncated_to_budget" | "self_addresses_unset" | "import_in_progress"[] | yes |

### ExportRow

### ExportSnapshot

| field | type | required |
|---|---|---|
| `key` | string | yes |
| `status` | "planned" | "partial" | "written" | yes |
| `as_of` | integer | yes |
| `end_as_of` | integer | null | yes |
| `consistent` | boolean | null | yes |
| `pages` | integer | yes |
| `bytes` | integer | null | yes |
| `sha256` | string | null | yes |
| `written_at` | string | null | yes |

### ExportSnapshotEnvelope

| field | type | required |
|---|---|---|
| `items` | ExportSnapshot[] | yes |
| `count` | integer | yes |
| `total` | integer | yes |
| `next_cursor` | string | null | yes |
| `warnings` | "truncated_to_budget" | "self_addresses_unset" | "import_in_progress"[] | yes |
| `dry_run` | boolean | yes |

### Features

| field | type | required |
|---|---|---|
| `files` | boolean | yes |
| `access` | boolean | yes |
| `mail` | boolean | yes |

### FindEnvelope

| field | type | required |
|---|---|---|
| `items` | FindRow[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### FindRow

| field | type | required |
|---|---|---|
| `type` | "contact" | "org" | "deal" | "interaction" | "transcript" | yes |
| `ref` | string | yes |
| `name` | string | yes |
| `detail` | string | yes |
| `rank` | number | yes |

### FollowUp

| field | type | required |
|---|---|---|
| `ref` | string | null | yes |
| `title` | string | yes |
| `body` | string | null | yes |
| `due_on` | string | null | yes |
| `status` | "open" | "done" | "dropped" | yes |
| `done_at` | string | null | yes |
| `outcome` | string | null | yes |
| `contact` | object | yes |
| `org` | OrgSummary | yes |
| `deal` | DealTitleSummary | yes |
| `interaction` | string | null | yes |
| `external_ref` | string | null | yes |
| `owner_id` | string | yes |
| `rev` | integer | yes |
| `created_at` | string | yes |
| `updated_at` | string | yes |
| `archived_at` | string | null | yes |
| `deleted` | true | no |
| `provisional` | string | no |

### FollowUpAssertEnvelope

| field | type | required |
|---|---|---|
| `items` | FollowUp[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |
| `outcome` | "created" | "updated" | "unchanged" | yes |

### FollowUpClose

| field | type | required |
|---|---|---|
| `outcome` | string | no |
| `log` | object | no |

### FollowUpEnvelope

| field | type | required |
|---|---|---|
| `items` | FollowUp[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### FollowUpIn

| field | type | required |
|---|---|---|
| `title` | string | yes |
| `body` | string | no |
| `due_on` | string | null | no |
| `contact` | string | no |
| `org` | string | no |
| `deal` | string | no |
| `interaction` | string | no |
| `external_ref` | string | no |

### FollowUpPatch

| field | type | required |
|---|---|---|
| `title` | string | no |
| `body` | string | null | no |
| `due_on` | string | null | no |
| `contact` | string | null | no |
| `org` | string | null | no |
| `deal` | string | null | no |
| `external_ref` | string | no |

### Health

| field | type | required |
|---|---|---|
| `ok` | true | yes |
| `version` | string | yes |
| `commit` | string | yes |
| `migrations_applied` | integer | yes |
| `features` | Features | yes |
| `auth_misconfigured` | true | no |

### Import

| field | type | required |
|---|---|---|
| `ref` | string | null | yes |
| `kind` | "snapshot" | "orgs_csv" | "contacts_csv" | "interactions_jsonl" | "verdicts" | "seed" | yes |
| `source` | string | yes |
| `sha256` | string | yes |
| `status` | "open" | "committed" | "aborted" | "dry_run" | null | yes |
| `counts` | object | yes |
| `rejects` | ImportReject[] | yes |
| `actor` | string | yes |
| `created_at` | string | null | yes |
| `finished_at` | string | null | yes |
| `owner_id` | string | yes |
| `outcome` | "created" | "unchanged" | no |
| `lines` | ImportLine[] | no |

### ImportChunk

| field | type | required |
|---|---|---|
| `session` | string | yes |
| `seq` | integer | yes |
| `sha256` | string | yes |
| `outcome` | "created" | "unchanged" | yes |
| `ranges` | object | null | yes |
| `received_at` | string | null | yes |

### ImportChunkEnvelope

| field | type | required |
|---|---|---|
| `items` | ImportChunk[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | object[] | no |

### ImportEnvelope

| field | type | required |
|---|---|---|
| `items` | Import[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | object[] | no |

### ImportLine

| field | type | required |
|---|---|---|
| `line` | integer | yes |
| `action` | "create" | "update" | "skip" | "reject" | yes |
| `entity` | "org" | "contact" | "interaction" | yes |
| `ref` | string | null | yes |
| `name` | string | null | yes |
| `outcome` | "created" | "updated" | "unchanged" | no |
| `auto_created` | true | no |
| `code` | string | no |
| `error` | string | no |

### ImportReject

| field | type | required |
|---|---|---|
| `line` | integer | yes |
| `error` | string | yes |
| `code` | string | yes |

### ImportSession

| field | type | required |
|---|---|---|
| `ref` | string | null | yes |
| `source` | string | yes |
| `sha256` | string | yes |
| `status` | "open" | "committed" | "aborted" | yes |
| `actor` | string | yes |
| `created_at` | string | yes |
| `finished_at` | string | null | yes |
| `owner_id` | string | yes |
| `chunk_count` | integer | yes |
| `received` | integer[] | yes |
| `missing` | integer[] | yes |
| `tables` | object | yes |
| `migrations` | string[] | yes |
| `commit_progress` | object | null | yes |
| `committed` | boolean | no |
| `import` | string | null | yes |

### ImportSessionEnvelope

| field | type | required |
|---|---|---|
| `items` | ImportSession[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | object[] | no |

### Interaction

| field | type | required |
|---|---|---|
| `ref` | string | null | yes |
| `kind` | "call" | "meeting" | "email" | "message" | "note" | yes |
| `occurred_on` | string | yes |
| `occurred_at` | string | null | yes |
| `duration_s` | integer | null | yes |
| `direction` | "in" | "out" | null | yes |
| `summary` | string | yes |
| `body` | string | null | yes |
| `external_ref` | string | null | yes |
| `source` | string | null | yes |
| `org` | OrgSummary | yes |
| `deal` | DealTitleSummary | yes |
| `with` | ContactSummary[] | yes |
| `transcript` | TranscriptMeta | yes |
| `attachments` | AttachmentMeta[] | no |
| `legacy_transcript_path` | string | null | yes |
| `owner_id` | string | yes |
| `rev` | integer | yes |
| `created_at` | string | yes |
| `updated_at` | string | yes |
| `archived_at` | string | null | yes |
| `outcome` | "created" | "updated" | "unchanged" | no |
| `deleted` | true | no |
| `provisional` | string | no |

### InteractionEnvelope

| field | type | required |
|---|---|---|
| `items` | Interaction[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### InteractionIn

| field | type | required |
|---|---|---|
| `kind` | "call" | "meeting" | "email" | "message" | "note" | yes |
| `summary` | string | yes |
| `date` | string | no |
| `occurred_at` | string | no |
| `tz` | string | no |
| `duration_s` | integer | no |
| `direction` | "in" | "out" | no |
| `external_ref` | string | no |
| `source` | string | no |
| `body` | string | no |
| `org` | string | no |
| `deal` | string | no |
| `with` | string[] | no |

### InteractionPatch

| field | type | required |
|---|---|---|
| `kind` | "call" | "meeting" | "email" | "message" | "note" | no |
| `summary` | string | no |
| `date` | string | no |
| `occurred_at` | string | no |
| `tz` | string | no |
| `duration_s` | integer | no |
| `direction` | "in" | "out" | no |
| `external_ref` | string | no |
| `source` | string | null | no |
| `body` | string | null | no |
| `org` | string | null | no |
| `deal` | string | null | no |
| `add_with` | string[] | no |
| `rm_with` | string[] | no |

### Limits

| field | type | required |
|---|---|---|
| `limit_max` | integer | yes |
| `d1_max_queries` | integer | yes |
| `d1_max_params` | integer | yes |
| `d1_batch_counts_as` | "statements" | "one" | yes |
| `reserved_queries` | integer | yes |
| `batch_max_ops` | integer | yes |
| `in_list_max` | integer | yes |
| `import_chunk_rows` | integer | yes |
| `csv_max_rows` | integer | yes |
| `ingest_max_threads` | integer | yes |
| `resolve_max_handles` | integer | yes |
| `resolve_max_queries` | integer | yes |
| `tag_members_max` | integer | yes |
| `transcript_segments_per_request` | integer | yes |
| `chunk_rows` | integer | yes |
| `response_budget_bytes` | integer | yes |
| `max_upload_bytes` | integer | yes |

### Link

| field | type | required |
|---|---|---|
| `contact` | ContactSummary | yes |
| `type` | string | yes |
| `note` | string | null | yes |
| `created_at` | string | yes |

### LinkIn

| field | type | required |
|---|---|---|
| `related` | string | yes |
| `type` | string | yes |
| `note` | string | no |

### Members

| field | type | required |
|---|---|---|
| `refs` | string[] | yes |

### Move

| field | type | required |
|---|---|---|
| `stage` | string | yes |
| `note` | string | no |

### Org

| field | type | required |
|---|---|---|
| `ref` | string | null | yes |
| `name` | string | yes |
| `category` | string | null | yes |
| `website` | string | null | yes |
| `linkedin` | string | null | yes |
| `location` | string | null | yes |
| `focus` | string | null | yes |
| `context` | string | null | yes |
| `relationship_hint` | string | null | yes |
| `provenance_sources` | string | null | yes |
| `provenance_details` | string | null | yes |
| `cadence_days` | integer | null | yes |
| `owner_id` | string | yes |
| `rev` | integer | yes |
| `created_at` | string | yes |
| `updated_at` | string | yes |
| `archived_at` | string | null | yes |
| `merged_into` | string | null | yes |
| `merged_from` | string | no |
| `domains` | OrgDomain[] | no |
| `tags` | TagSummary[] | no |
| `signals` | Signals | no |
| `team` | object[] | no |
| `outcome` | "created" | "updated" | "unchanged" | no |
| `deleted` | true | no |
| `provisional` | string | no |

### OrgAssert

| field | type | required |
|---|---|---|
| `name` | string | yes |
| `category` | string | null | no |
| `website` | string | null | no |
| `linkedin` | string | null | no |
| `location` | string | null | no |
| `focus` | string | null | no |
| `context` | string | null | no |
| `hint` | string | null | no |
| `source` | string | no |
| `detail` | string | no |
| `cadence_days` | integer | null | no |
| `domains` | string[] | no |
| `context_append` | string | no |

### OrgDomain

| field | type | required |
|---|---|---|
| `domain` | string | yes |
| `is_primary` | boolean | yes |
| `source` | string | null | yes |

### OrgDomainEnvelope

| field | type | required |
|---|---|---|
| `items` | OrgDomain[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### OrgEnvelope

| field | type | required |
|---|---|---|
| `items` | Org[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### OrgIn

| field | type | required |
|---|---|---|
| `name` | string | yes |
| `category` | string | null | no |
| `website` | string | null | no |
| `linkedin` | string | null | no |
| `location` | string | null | no |
| `focus` | string | null | no |
| `context` | string | null | no |
| `hint` | string | null | no |
| `source` | string | no |
| `detail` | string | no |
| `cadence_days` | integer | null | no |
| `domains` | string[] | no |

### OrgPatch

| field | type | required |
|---|---|---|
| `name` | string | no |
| `category` | string | null | no |
| `website` | string | null | no |
| `linkedin` | string | null | no |
| `location` | string | null | no |
| `focus` | string | null | no |
| `context` | string | null | no |
| `hint` | string | null | no |
| `source` | string | no |
| `detail` | string | no |
| `cadence_days` | integer | null | no |
| `context_append` | string | no |

### OrgSummary

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `name` | string | yes |

### PinIn

| field | type | required |
|---|---|---|
| `thread` | string | yes |
| `ref` | string | yes |

### Pipeline

| field | type | required |
|---|---|---|
| `ref` | string | null | yes |
| `name` | string | yes |
| `position` | integer | yes |
| `stages` | object[] | yes |
| `deleted_stage` | object | no |
| `stage` | object | no |
| `rev` | integer | yes |
| `created_at` | string | yes |
| `updated_at` | string | yes |
| `archived_at` | string | null | yes |
| `outcome` | "created" | "updated" | "unchanged" | no |
| `deleted` | true | no |
| `provisional` | string | no |

### PipelineEnvelope

| field | type | required |
|---|---|---|
| `items` | Pipeline[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### PipelineIn

| field | type | required |
|---|---|---|
| `name` | string | yes |
| `stages` | object[] | no |

### PipelinePatch

| field | type | required |
|---|---|---|
| `name` | string | no |

### PipelineSummary

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `name` | string | yes |

### PlannedChange

| field | type | required |
|---|---|---|
| `entity` | string | yes |
| `ref` | string | null | yes |
| `op` | string | yes |
| `field` | string | null | yes |
| `before` | object | no |
| `after` | object | no |

### Reorder

| field | type | required |
|---|---|---|
| `order` | string[] | yes |

### ResolveEnvelope

| field | type | required |
|---|---|---|
| `items` | ResolvedHandle[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### ResolveIn

| field | type | required |
|---|---|---|
| `handles` | string[] | yes |

### ResolvedHandle

| field | type | required |
|---|---|---|
| `handle` | string | yes |
| `match` | "contact_email" | "org_domain" | "self" | "freemail" | "none" | yes |
| `contact` | object | no |
| `org` | object | no |

### SchemaEntity

| field | type | required |
|---|---|---|
| `entity` | string | yes |
| `prefix` | string | yes |
| `table` | string | yes |
| `fields` | SchemaField[] | yes |

### SchemaErrorCode

| field | type | required |
|---|---|---|
| `code` | string | yes |
| `http` | integer | yes |
| `exit` | integer | yes |
| `meaning` | string | yes |

### SchemaField

| field | type | required |
|---|---|---|
| `name` | string | yes |
| `type` | string | yes |
| `required` | boolean | yes |
| `create` | boolean | yes |
| `edit` | boolean | yes |
| `output` | boolean | yes |
| `enum` | string[] | no |
| `max_length` | integer | no |

### SchemaReport

| field | type | required |
|---|---|---|
| `version` | string | yes |
| `entities` | SchemaEntity[] | yes |
| `enums` | object | yes |
| `ref_prefixes` | object | yes |
| `error_codes` | SchemaErrorCode[] | yes |
| `limits` | Limits | yes |
| `features` | WhoamiFeatures | yes |
| `reports` | object | yes |

### SegmentEnvelope

| field | type | required |
|---|---|---|
| `items` | TranscriptSegment[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### SendStatus

### SessionIn

| field | type | required |
|---|---|---|
| `source` | string | yes |
| `sha256` | string | yes |
| `manifest` | object | yes |

### ShowEnvelope

| field | type | required |
|---|---|---|
| `items` | ShowRecord[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### ShowRecord

### Signals

| field | type | required |
|---|---|---|
| `first_touch_on` | string | null | yes |
| `last_touch_on` | string | null | yes |
| `days_since_touch` | integer | null | yes |
| `touches_90d` | integer | yes |
| `first_email_at` | string | null | yes |
| `last_email_at` | string | null | yes |
| `open_follow_ups` | integer | yes |
| `next_follow_up_on` | string | null | yes |
| `cadence_days` | integer | null | yes |
| `cadence_due` | boolean | yes |

### StageIn

| field | type | required |
|---|---|---|
| `name` | string | yes |
| `rot_days` | integer | null | no |
| `after` | string | no |
| `first` | true | no |

### StageMove

| field | type | required |
|---|---|---|
| `deal` | DealTitleSummary | yes |
| `from` | object | yes |
| `to` | StageSummary | yes |
| `moved_at` | string | yes |
| `note` | string | null | yes |

### StagePatch

| field | type | required |
|---|---|---|
| `name` | string | no |
| `rot_days` | integer | null | no |

### StageSummary

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `name` | string | yes |

### StaleEnvelope

| field | type | required |
|---|---|---|
| `items` | StaleRow[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### StaleRow

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `name` | string | yes |
| `last_touch_on` | string | null | yes |
| `days_since_touch` | integer | null | yes |
| `cadence_days` | integer | null | yes |
| `reason` | "cadence" | "days" | yes |

### Status

| field | type | required |
|---|---|---|
| `counts` | object | yes |
| `last_logged` | object | null | yes |
| `never_contacted` | integer | yes |
| `stale_90d` | integer | yes |
| `rotting_deals` | integer | yes |
| `cadence_due` | integer | yes |
| `overdue_follow_ups` | integer | yes |
| `usage` | object | yes |
| `migrations_applied` | integer | yes |
| `last_mail_push` | string | null | yes |
| `warnings` | string[] | yes |

### Tag

| field | type | required |
|---|---|---|
| `ref` | string | null | yes |
| `name` | string | yes |
| `note` | string | null | yes |
| `counts` | object | no |
| `members` | TagMember[] | no |
| `owner_id` | string | yes |
| `rev` | integer | yes |
| `created_at` | string | yes |
| `updated_at` | string | yes |
| `archived_at` | string | null | yes |
| `outcome` | "created" | "updated" | "unchanged" | no |
| `deleted` | true | no |
| `provisional` | string | no |

### TagEnvelope

| field | type | required |
|---|---|---|
| `items` | Tag[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### TagIn

| field | type | required |
|---|---|---|
| `name` | string | yes |
| `note` | string | no |

### TagMember

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `entity` | "org" | "contact" | "deal" | yes |
| `name` | string | yes |
| `tagged_at` | string | yes |

### TagPatch

| field | type | required |
|---|---|---|
| `name` | string | no |
| `note` | string | null | no |

### TagSummary

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `name` | string | yes |

### ThreadIn

| field | type | required |
|---|---|---|
| `thread_ref` | string | yes |
| `account` | string | yes |
| `subject` | object | yes |
| `first_at` | string | yes |
| `last_at` | string | yes |
| `message_count` | integer | yes |
| `last_direction` | "in" | "out" | null | yes |
| `automated` | object | yes |
| `participants` | object[] | yes |

### ThreadLink

| field | type | required |
|---|---|---|
| `id` | integer | null | yes |
| `ref` | string | null | yes |
| `entity` | "contact" | "org" | "deal" | yes |
| `assigned` | "auto" | "manual" | yes |
| `matched_by` | "contact_email" | "org_domain" | null | yes |

### ThreadOut

| field | type | required |
|---|---|---|
| `thread` | string | null | yes |
| `thread_ref` | string | yes |
| `account` | string | yes |
| `outcome` | "created" | "updated" | "unchanged" | "stale" | "emptied" | "deferred" | "rejected" | yes |
| `links` | ThreadLink[] | yes |
| `interaction` | string | null | yes |
| `error` | object | no |

### ThreadOutEnvelope

| field | type | required |
|---|---|---|
| `items` | ThreadOut[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |
| `autocreated` | Autocreated[] | no |

### ThreadsIngest

| field | type | required |
|---|---|---|
| `threads` | ThreadIn[] | yes |

### TimelineEnvelope

| field | type | required |
|---|---|---|
| `items` | TimelineItem[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### TimelineItem

### Today

| field | type | required |
|---|---|---|
| `date` | string | yes |
| `tz` | string | yes |
| `follow_ups` | object | yes |
| `rotting_deals` | integer | yes |
| `cadence_due` | StaleRow[] | yes |
| `recent_changes` | integer | yes |

### TranscriptEnvelope

| field | type | required |
|---|---|---|
| `items` | TranscriptMeta[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### TranscriptMeta

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `interaction` | string | yes |
| `sha256` | string | yes |
| `bytes` | integer | yes |
| `format` | "md" | "txt" | "json" | "vtt" | "srt" | yes |
| `speakers` | string[] | yes |
| `duration_s` | integer | null | yes |
| `language` | string | null | yes |
| `source` | string | null | yes |
| `segments_indexed` | integer | yes |
| `segments_total` | integer | yes |
| `created_at` | string | yes |
| `archived_at` | string | null | yes |

### TranscriptSegment

| field | type | required |
|---|---|---|
| `transcript` | string | yes |
| `seq` | integer | yes |
| `speaker` | string | null | yes |
| `start_ms` | integer | null | yes |
| `end_ms` | integer | null | yes |
| `text` | string | yes |

### TranscriptUpload

| field | type | required |
|---|---|---|
| `file` | string | yes |

### TranscriptWriteEnvelope

| field | type | required |
|---|---|---|
| `items` | TranscriptMeta[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |
| `outcome` | "created" | "unchanged" | no |

### UnmatchedCall

| field | type | required |
|---|---|---|
| `ref` | string | yes |
| `occurred_on` | string | yes |
| `summary` | string | yes |
| `external_ref` | string | null | yes |
| `transcript` | string | null | yes |

### UnmatchedCallsEnvelope

| field | type | required |
|---|---|---|
| `items` | UnmatchedCall[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### UnmatchedEnvelope

| field | type | required |
|---|---|---|
| `items` | UnmatchedRow[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### UnmatchedRow

| field | type | required |
|---|---|---|
| `handle` | string | yes |
| `display_name` | string | null | yes |
| `thread_count` | integer | yes |
| `two_way` | boolean | yes |
| `last_at` | string | yes |
| `domain` | string | yes |
| `domain_org` | string | no |

### Verdict

| field | type | required |
|---|---|---|
| `entity` | "contact" | "org" | yes |
| `left` | string | yes |
| `right` | string | yes |
| `verdict` | "distinct" | "parked" | yes |
| `note` | string | null | yes |
| `actor` | string | yes |
| `source` | string | null | yes |
| `decided_at` | string | yes |
| `owner_id` | string | yes |
| `deleted` | boolean | no |

### VerdictEnvelope

| field | type | required |
|---|---|---|
| `items` | Verdict[] | yes |
| `count` | integer | yes |
| `total` | integer | null | yes |
| `next_cursor` | string | null | yes |
| `warnings` | string[] | yes |
| `dry_run` | boolean | yes |
| `planned_changes` | PlannedChange[] | no |
| `has_more` | boolean | no |

### VerdictIn

| field | type | required |
|---|---|---|
| `entity` | "contact" | "org" | yes |
| `left` | string | yes |
| `right` | string | yes |
| `verdict` | "distinct" | "parked" | yes |
| `note` | string | no |

### Whoami

| field | type | required |
|---|---|---|
| `door` | "bearer" | "access" | "binding" | "system" | yes |
| `actor` | string | yes |
| `credential` | string | yes |
| `owner_id` | string | yes |
| `scope` | "rw" | "ro" | yes |
| `features` | WhoamiFeatures | yes |
| `self_addresses` | boolean | yes |
| `import_open` | integer | null | yes |
| `maintenance` | boolean | yes |
| `tz` | string | yes |

### WhoamiFeatures

| field | type | required |
|---|---|---|
| `files` | boolean | yes |
| `access` | boolean | yes |
| `mail` | boolean | yes |
| `email_autocreate` | string | yes |
