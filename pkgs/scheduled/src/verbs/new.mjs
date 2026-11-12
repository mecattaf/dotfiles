// scheduled new ID --cron EXPR --tz ZONE (--prompt TEXT | --prompt-file PATH) [--name N]
// A new item is always written "enabled": false: an item is armed only by a deliberate edit.
import { locate, writeItem, guarded, parseFlags, WriteError } from '../lib/write.mjs';

const USAGE = 'usage: scheduled new ID --cron EXPR --tz ZONE (--prompt TEXT | --prompt-file PATH) [--name N]';

export function minimalItem({ name, cron, tz, prompt, promptFile, at }) {
  const job = promptFile !== undefined ? `"prompt-file": ${JSON.stringify(promptFile)}` : `"prompt": ${JSON.stringify(prompt)}`;
  return `// Created by scheduled new at ${at}. Off until "enabled" is set to true.
{
  ${name !== undefined ? `"name": ${JSON.stringify(name)},\n  ` : ''}"enabled": false,
  "on": {
    "schedule": [
      { "cron": ${JSON.stringify(cron)}, "timezone": ${JSON.stringify(tz)} }
    ]
  },
  "job": {
    ${job}
  }
}
`;
}

export async function main(args, ctx) {
  return guarded(ctx, async () => {
    const flags = parseFlags(args, { values: ['--cron', '--tz', '--prompt', '--prompt-file', '--name'] });
    const hasPrompt = flags.prompt !== undefined;
    const hasFile = flags['prompt-file'] !== undefined;
    if (flags.positional.length !== 1 || !flags.cron || !flags.tz || hasPrompt === hasFile) throw new WriteError(USAGE, 2);
    const target = await locate(ctx, flags.positional[0]);
    const text = minimalItem({ name: flags.name, cron: flags.cron, tz: flags.tz, prompt: flags.prompt, promptFile: flags['prompt-file'],
      at: (ctx.now?.() ?? new Date()).toISOString() });
    const res = await writeItem(ctx, { path: target.path, bytes: Buffer.from(text), expect: 'none' });
    ctx.out(`${target.id} ${res.revision} ${res.path}\n`);
    return 0;
  });
}
