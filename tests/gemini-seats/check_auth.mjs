// Exercise the real CLI settings loader without signing in or using a model.
import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { pathToFileURL } from 'node:url'

const root = await mkdtemp(join(tmpdir(), 'gemini-auth-settings-'))
try {
  const workspace = join(root, 'project')
  await mkdir(join(root, '.gemini'), { recursive: true })
  await mkdir(join(workspace, '.gemini'), { recursive: true })
  const apiSettings = JSON.stringify({ security: { auth: { selectedType: 'gemini-api-key' } } })
  await writeFile(join(root, '.gemini/settings.json'), apiSettings, { mode: 0o600 })
  await writeFile(join(workspace, '.gemini/settings.json'), apiSettings, { mode: 0o600 })
  process.env.GEMINI_CLI_HOME = root
  process.env.GEMINI_CLI_SYSTEM_SETTINGS_PATH = process.argv[3]
  process.env.GOOGLE_GENAI_USE_GCA = 'true'
  delete process.env.GEMINI_CLI_AUTH_OVERRIDE
  const { loadSettings, mergeSettings } = await import(pathToFileURL(process.argv[2]).href)
  const policy = JSON.parse(await readFile(process.argv[3], 'utf8'))
  for (let restart = 0; restart < 3; restart++) {
    // The Nix sandbox remaps /nix/store ownership; the real system-settings
    // loader correctly rejects that as non-root-owned. Exercise upstream's
    // merge policy here; also exercise the complete loader after installation
    // on NAS, with GEMINI_AUTH_CHECK_LOAD=1 and the root-owned /etc policy.
    const settings = process.env.GEMINI_AUTH_CHECK_LOAD === '1'
      ? loadSettings(workspace).merged
      : mergeSettings(policy, {}, JSON.parse(apiSettings), JSON.parse(apiSettings), true)
    assert.equal(settings.security.auth.selectedType, 'oauth-personal')
    assert.equal(settings.security.auth.enforcedType, 'oauth-personal')
    assert.equal(settings.experimental.autoMemory, false)
    assert.equal(process.env.GEMINI_CLI_AUTH_OVERRIDE, undefined)
  }
  console.log('Real Gemini settings precedence: Google OAuth survives repeated loads and API-key user/project settings')
} finally {
  await rm(root, { recursive: true, force: true })
}
