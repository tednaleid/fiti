// ABOUTME: Regenerates JSON fixtures for the Swift PerfectFreehand port by
// ABOUTME: running the upstream TS implementation against fixed inputs.

import { getStroke, type StrokeOptions } from 'perfect-freehand'
import { writeFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

type FixtureFile = {
    name: string
    input: Array<[number, number] | [number, number, number]>
    options: StrokeOptions
    // `expected` is regenerated; whatever's in the file gets overwritten.
    expected?: number[][]
}

const files = readdirSync(here).filter(f => f.endsWith('.json') && f !== 'package.json' && f !== 'tsconfig.json')

for (const file of files) {
    const path = join(here, file)
    const fixture: FixtureFile = JSON.parse(await Bun.file(path).text())
    // The Swift port's `StrokeInputPoint` is object-shaped, which means a
    // missing pressure in TS gets defaulted to DEFAULT_PRESSURE (0.5) for
    // EVERY point including the first — TS's array path defaults the first
    // point to DEFAULT_FIRST_PRESSURE (0.25) instead. To match the Swift
    // port's behaviour byte-for-byte we feed upstream object-shape inputs.
    const objectInput = fixture.input.map(row => ({
        x: row[0],
        y: row[1],
        pressure: row.length > 2 ? row[2] : undefined,
    }))
    const polygon = getStroke(objectInput, fixture.options)
    fixture.expected = polygon
    writeFileSync(path, JSON.stringify(fixture, null, 2) + '\n')
    console.log(`✓ ${file} — ${polygon.length} vertices`)
}
