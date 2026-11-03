{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nodejs,
}:
# @jiesou/dsh-opencode-zen-free-provider 0.1.28 (jiesou/dsh-opencode-zen-free-provider,
# MIT, tag 0.1.28): OpenCode Zen's `-free` models as a dsh provider, the known
# workaround Tom chose in place of installing the OpenCode CLI (2026-11-03).
# Mounted only in the hand-run `zen` profile (../../dsh/config.nix).
#
# Upstream commits lib/ (built in the same commit as src/, checked
# structurally here), has no runtime dependency, and imports only dsh peers
# the running dsh supplies, so there is no build step and no pnpm fetch.
# Its manifest ranges (pi-ai ^0.85.1) predate this dsh's pi-ai 1.3.0;
# checks.dsh-zen boots it against the real one.
#
# What it does, plainly: it makes dsh look like the OpenCode CLI. It forces an
# opencode/<version> User-Agent and x-opencode-* headers on opencode.ai
# requests, mints ses_ session ids in opencode's format and pads placeholder
# tools, because Zen's free tier answers a plain client's FIRST call with 429
# FreeUsageLimitError (a client-fingerprint gate, measured 2026-11-03 on all
# four keys). Network at mount: the opencode.ai catalog, models.dev and unpkg
# for the UA version (offline: the 1.19.0 fallback and the last-good catalog
# cache under $DSH_HOME/cache). Every prompt leaves the machine to opencode.ai.
#
# The key: the plugin resolves OPENCODE_ZEN_FREE_API_KEY only through dsh's
# `credentials` service (never process.env) and falls back to the anonymous
# bearer `public`; the `zen` profile re-enables that service for this reason.
stdenvNoCC.mkDerivation {
  pname = "dsh-opencode-zen-free-provider";
  version = "0.1.28";

  src = fetchFromGitHub {
    owner = "jiesou";
    repo = "dsh-opencode-zen-free-provider";
    rev = "7e779c73d2127327be529908ffc5a834934e8598"; # tag 0.1.28
    hash = "sha256-kH3IYGHA1zGsEYN4dXIR7VnQD5joezKBbxt0Nb0TOmA=";
  };

  nativeBuildInputs = [ nodejs ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r lib package.json cordis.patch.yml LICENSE README.md README.en.md $out/
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node --check $out/lib/index.js
    node --input-type=module -e '
      import { readFileSync } from "node:fs";
      const out = process.argv[1];
      const m = JSON.parse(readFileSync(out + "/package.json", "utf8"));
      if (m.version !== "0.1.28") throw new Error("unexpected version");
      if (m.dsh.bundle.patch !== "./cordis.patch.yml") throw new Error("bundle patch moved");
      if (m.dependencies) throw new Error("runtime dependency appeared");
      // Every non-relative, non-node import must be a declared peer.
      const js = readFileSync(out + "/lib/index.js", "utf8");
      for (const [, spec] of js.matchAll(/from \x27([^\x27]+)\x27/g)) {
        if (spec.startsWith("node:")) continue;
        const name = spec.split("/").slice(0, spec.startsWith("@") ? 2 : 1).join("/");
        if (!(name in m.peerDependencies)) throw new Error("undeclared import " + spec);
      }
      // The only network hosts the plugin may name.
      const hosts = new Set([...js.matchAll(/https:\/\/([a-z.]+)/g)].map(x => x[1]));
      for (const h of hosts) if (!["opencode.ai", "unpkg.com", "models.dev"].includes(h))
        throw new Error("new host " + h);
      // The key path the profile relies on: credentials service, else public.
      if (!js.includes("credentialRef(\x27OPENCODE_ZEN_FREE_API_KEY\x27)")) throw new Error("key ref moved");
      if (!js.includes("return \x27public\x27")) throw new Error("anonymous fallback moved");
    ' "$out"
    runHook postInstallCheck
  '';

  meta = {
    description = "OpenCode Zen free models as a dsh provider (jiesou), committed lib/ unmodified";
    homepage = "https://github.com/jiesou/dsh-opencode-zen-free-provider";
    license = lib.licenses.mit;
  };
}
