// Exercise the real CLI settings loader without signing in or using a model.
import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises'
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
  const { loadSettings } = await import(pathToFileURL(process.argv[2]).href)
  for (let restart = 0; restart < 3; restart++) {
    const settings = loadSettings(workspace)
    assert.equal(settings.merged.security.auth.selectedType, 'oauth-personal')
    assert.equal(settings.merged.security.auth.enforcedType, 'oauth-personal')
    assert.equal(settings.merged.experimental.autoMemory, false)
    assert.equal(process.env.GEMINI_CLI_AUTH_OVERRIDE, undefined)
  }
  console.log('Real Gemini settings loader: Google OAuth survives repeated loads and API-key user/project settings')
} finally {
  await rm(root, { recursive: true, force: true })
}
