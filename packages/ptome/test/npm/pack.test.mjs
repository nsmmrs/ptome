// The npm package contains exactly the files it should.

import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { test } from 'node:test'

const packageDir = fileURLToPath(new URL('../../build/npm', import.meta.url))

test('npm pack lists the expected files', () => {
  const [report] = JSON.parse(
    execFileSync('npm', ['pack', '--dry-run', '--json', packageDir], { encoding: 'utf8' })
  )
  const files = report.files.map((file) => file.path).sort()
  // The parts of the core that load on demand (the PDF and EPUB backends),
  // as dart2js numbers them.
  const parts = files.filter((file) => /^parts\/part-\d+\.js$/.test(file))
  assert.ok(parts.length >= 2, `parts: ${parts}`)
  assert.deepEqual(files.filter((file) => !parts.includes(file)), [
    'LICENSE',
    'README.md',
    'bin/ptome.js',
    'browser.js',
    'node.cjs',
    'node.js',
    'package.json',
    'ptome.js',
    'src/api.g.js',
    'src/core.js',
    'src/index.js',
    'src/page_fonts.js',
    'types/index.d.cts',
    'types/index.d.ts',
  ])
})
