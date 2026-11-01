import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { join } from 'node:path';

const requests = [];
const server = createServer(async (request, response) => {
  let body = '';
  for await (const chunk of request) body += chunk;
  requests.push({ url: request.url, body: JSON.parse(body) });
  response.writeHead(200, { 'content-type': 'text/event-stream' });
  const chunk = (delta, finish_reason = null) => ({
    id: 'mnemon-smoke', object: 'chat.completion.chunk', created: 1,
    model: process.env.MNEMON_MODEL_ID,
    choices: [{ index: 0, delta, finish_reason }],
  });
  response.write(`data: ${JSON.stringify(chunk({ role: 'assistant', content: 'MNEMON_MOCK_READY' }))}\n\n`);
  response.write(`data: ${JSON.stringify(chunk({}, 'stop'))}\n\n`);
  response.end('data: [DONE]\n\n');
});
await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, '127.0.0.1', resolve);
});
try {
  const provider = JSON.parse(process.env.MNEMON_GUFO_CONFIG);
  provider.baseURL = `http://127.0.0.1:${server.address().port}/v1`;
  provider.retryPolicy = { mode: 'normal', maxRetries: 0 };
  const patch = join(process.env.TMPDIR, 'mock-provider.json');
  writeFileSync(patch, JSON.stringify([{ id: 'llm-pi-ai', config: { providers: { gufo: provider } } }]));
  const child = spawn(process.env.DSH_BIN, ['mnemon', '--patch', patch, 'Reply with MNEMON_MOCK_READY. Do not use tools.'], {
    cwd: process.cwd(), env: process.env, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '', stderr = '';
  child.stdout.on('data', chunk => { stdout += chunk; });
  child.stderr.on('data', chunk => { stderr += chunk; });
  const timeout = setTimeout(() => child.kill('SIGKILL'), 30_000);
  const code = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', resolve);
  });
  clearTimeout(timeout);
  assert.equal(code, 0, stderr);
  assert.match(stdout, /MNEMON_MOCK_READY/u);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, '/v1/chat/completions');
  const names = requests[0].body.tools.map(tool => tool.function.name);
  for (const name of ['mnemon_view_route', 'mnemon_view_action', 'mnemon_document_search', 'mnemon_document_create', 'mnemon_recall', 'mnemon_remember']) {
    assert.ok(names.includes(name), `Mnemon tool missing from actual DSH turn: ${name}`);
  }
  assert.equal(requests[0].body.model, process.env.MNEMON_MODEL_ID);
  console.log('Mnemon DSH turn: native/document tools reached the mock OpenAI provider');
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
