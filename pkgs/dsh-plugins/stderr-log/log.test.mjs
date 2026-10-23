// Unit test for index.js with a fake logger; no dsh.
import test from 'node:test'
import assert from 'node:assert/strict'
import { apply, render } from './index.js'

const msg = (type, ...args) => ({ name: 'jev', type, args })

test('error, info and warn print; debug does not', () => {
  assert.equal(render(msg('info', '[jevcore] ready · provider=mock')), 'dsh: jev info: [jevcore] ready · provider=mock\n')
  assert.equal(render(msg('warn', 'config at %C failed', '/x')), 'dsh: jev warn: config at /x failed\n')
  assert.match(render(msg('error', new Error('boom'))), /^dsh: jev error: Error: boom\n {4}at /)
  assert.equal(render(msg('debug', 'noise')), undefined)
  assert.equal(render(undefined), undefined)
})

test('a long line is capped', () => {
  const line = render(msg('info', 'x'.repeat(5000)))
  assert.equal(line.length, 'dsh: jev info: '.length + 4096 + 3 + 1)
})

test('the backlog prints first, then live messages through the exporter', () => {
  const out = []
  let exporter
  const ctx = {
    logger: {
      buffer: [msg('info', 'before'), msg('debug', 'hidden')],
      exporter(e) { exporter = e },
    },
  }
  apply(ctx, {}, (line) => out.push(line))
  assert.equal(exporter.levels.default, 2)
  exporter.export(msg('warn', 'after'))
  assert.deepEqual(out, ['dsh: jev info: before\n', 'dsh: jev warn: after\n'])
})
