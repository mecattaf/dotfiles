const rt = typeof Bun !== "undefined" ? "bun" : "node";
console.log(JSON.stringify({ rt, hrtimeMs: Number(process.hrtime.bigint() / 1000000n), perfNow: Math.round(performance.now()) }));
