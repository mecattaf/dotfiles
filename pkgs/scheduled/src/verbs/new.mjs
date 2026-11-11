// scheduled new ID --cron EXPR --tz ZONE --prompt TEXT [--paused] [--by WHO] (DESIGN 10.1)
import { locate, writeWorkflow, guarded, parseFlags, byOf, WriteError } from '../lib/write.mjs';

export function minimalWorkflow({ stem, cron, tz, prompt, paused, by, at }) {
  return `// Created by scheduled new (by ${by}, ${at}).
{
  "name": ${JSON.stringify(stem)},
  "enabled": ${paused ? 'false' : 'true'},
  "on": {
    "schedule": [
      { "cron": ${JSON.stringify(cron)}, "timezone": ${JSON.stringify(tz)} }
    ]
  },
  "job": {
    "prompt": ${JSON.stringify(prompt)}
  }
}
`;
}

export async function main(args, ctx) {
  return guarded(ctx, async () => {
    const flags = parseFlags(args, { allow: ['--cron', '--tz', '--prompt', '--paused', '--by'] });
    if (flags.positional.length !== 1 || !flags.cron || !flags.tz || !flags.prompt) {
      throw new WriteError('usage: scheduled new ID --cron EXPR --tz ZONE --prompt TEXT [--paused]', 2);
    }
    const target = await locate(ctx, flags.positional[0]);
    const by = byOf(flags, ctx);
    const text = minimalWorkflow({ stem: target.stem, cron: flags.cron, tz: flags.tz, prompt: flags.prompt, paused: !!flags.paused,
      by, at: (ctx.now?.() ?? new Date()).toISOString() });
    const res = await writeWorkflow(ctx, { path: target.path, bytes: Buffer.from(text), by, id: target.id, expect: 'none' });
    ctx.out(`${target.id} ${res.revision} ${res.path}\n`);
    return 0;
  });
}
