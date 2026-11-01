import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const { createDocumentsMemorySource } = await import(pathToFileURL(
  join(process.env.MNEMON_PLUGIN, 'node_modules/dsh-mnemon-source-documents/lib/index.js'),
));
const original = join(process.cwd(), 'original-note.md');
const content = '# Synthetic overnight note\n\nThe copper badger chose the north gate.\n';
writeFileSync(original, content);
const definition = createDocumentsMemorySource({ dataDir: process.env.MNEMON_DATA_DIR });
const source = definition.create({ sourceInstanceKey: 'mnemon-source-documents', configuration: {} });
const scope = { workspaceId: process.cwd() };
const created = await source.manage({
  scope, mode: 'write', operation: 'mutate', confirmed: true,
  input: { action: 'create', title: 'Overnight note', content, sourcePaths: [original] },
});
assert.ok(created.revision);
const result = await source.manage({ scope, mode: 'read', operation: 'search', input: { query: 'copper badger' } });
assert.equal(result.value.results.length, 1);
assert.equal(result.value.results[0].content, content.trim());
assert.deepEqual(result.value.results[0].sourcePaths, ['original-note.md']);
assert.equal(readFileSync(original, 'utf8'), content);
console.log('Mnemon Documents: create, lexical search, provenance and original preserved');
