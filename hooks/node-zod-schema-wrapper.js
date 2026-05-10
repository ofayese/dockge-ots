#!/usr/bin/env node
/**
 * Hook: Detect Zod schemas not wrapped in z.object()
 * Flags: export const schema = z.string() or z.array(...) without z.object() wrapper.
 * Issue: Zod best practice is to always use z.object() for schemas to ensure consistency.
 */

const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
let failed = false;

for (const file of args) {
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
    continue;
  }

  try {
    const content = fs.readFileSync(file, 'utf8');
    const lines = content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Skip comments
      if (line.trim().startsWith('//') || line.trim().startsWith('/*')) {
        continue;
      }

      // Look for schema export patterns that are NOT z.object()
      // Patterns to flag:
      //   export const schema = z.string()
      //   export const schema = z.array(...)
      //   export const schema = z.union(...)
      //   const config = z.record(...)
      // Patterns OK:
      //   export const schema = z.object(...)
      //   const nested = z.object(...).strict()

      const schemaMatch = line.match(/(?:export\s+)?const\s+\w+\s*=\s*z\.(string|array|union|record|enum|intersection|discriminatedUnion|effect|refine|lazy|tuple|promise|date|never|nan|bigint|boolean|number|null|undefined|any)\s*[\(]/);

      if (schemaMatch) {
        // This is a schema without z.object() wrapper
        const type = schemaMatch[1];
        console.error(`${file}:${lineNum}: Zod schema should be wrapped in z.object() (found z.${type}): ${line.trim()}`);
        failed = true;
      }
    }
  } catch (err) {
    // Silently skip read errors
  }
}

process.exit(failed ? 1 : 0);
