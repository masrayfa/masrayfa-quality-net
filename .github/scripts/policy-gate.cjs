#!/usr/bin/env node
'use strict';

/**
 * Definition-of-Ready/Done policy gate.
 *
 * Single source of truth: imported by the `policy-gate` workflow, and runnable
 * locally against a synthetic payload for proof:
 *
 *   node .github/scripts/policy-gate.cjs <case.json>   # {"body": "...", "files": [...]}
 *
 * Exit 0 = policy satisfied, 1 = blocked (also fails the CI check).
 */

const REQUIRED_SECTIONS = [
  '## Spec / PRD',
  '## Acceptance criteria',
  '## Design plan',
  '## Test evidence',
];

// Any unchecked GitHub task-list item (`- [ ]`) anywhere in the body.
const UNCHECKED_TASK_RE = /^[ \t]*-[ \t]+\[[ \t]\]/m;
// A change under these trees is "source" and must be paired with a test change.
const SOURCE_RE = /^(api\/app|api\/config|api\/db|web\/src)\//;
const TEST_RE = /^(api\/spec\/|web\/src\/.*\.(test|spec)\.)/;

function sectionText(body, marker) {
  const lines = body.split(/\r?\n/);
  const start = lines.findIndex((line) => line.trim() === marker);
  if (start === -1) return null;
  const section = [];
  for (let i = start + 1; i < lines.length; i++) {
    if (/^##\s/.test(lines[i])) break; // next top-level section
    section.push(lines[i]);
  }
  return section.join('\n');
}

function evaluatePolicy({ body, files }) {
  if (typeof body !== 'string' || body.trim() === '') {
    // Fail closed: a missing/empty PR body is never a pass.
    return { pass: false, reasons: ['PR body is empty or missing - failing closed.'] };
  }

  const reasons = [];

  for (const marker of REQUIRED_SECTIONS) {
    const text = sectionText(body, marker);
    if (text === null) reasons.push(`Missing required section: "${marker}"`);
    else if (text.trim() === '') reasons.push(`Empty required section: "${marker}"`);
  }

  if (UNCHECKED_TASK_RE.test(body)) {
    reasons.push('Unchecked Definition-of-Ready checklist item(s) remain (`- [ ]`).');
  }

  const paths = (Array.isArray(files) ? files : []).map((f) =>
    typeof f === 'string' ? f : f.path || f.filename || ''
  );
  const source = paths.filter((p) => SOURCE_RE.test(p));
  const tests = paths.filter((p) => TEST_RE.test(p));
  if (source.length > 0 && tests.length === 0) {
    reasons.push(
      `Source change without a test change: ${source.join(', ')} ` +
        '(expected a changed file under api/spec/ or matching web/src/*.test.*|*.spec.*).'
    );
  }

  return { pass: reasons.length === 0, reasons };
}

module.exports = { evaluatePolicy, REQUIRED_SECTIONS };

if (require.main === module) {
  const fs = require('fs');
  const input = process.argv[2]
    ? fs.readFileSync(process.argv[2], 'utf8')
    : fs.readFileSync(0, 'utf8'); // stdin when no file given
  const result = evaluatePolicy(JSON.parse(input));
  if (result.pass) {
    console.log('policy-gate: PASS - Definition of Ready/Done satisfied.');
    process.exit(0);
  }
  console.error('policy-gate: BLOCKED');
  for (const reason of result.reasons) console.error('  - ' + reason);
  process.exit(1);
}
