#!/usr/bin/env node
'use strict';

/**
 * Release-gate policy.
 *
 * RELEASABLE only when BOTH hold:
 *   1. the quality net (ci.yml, reused via workflow_call) succeeded for the tag;
 *   2. assessment/risk-register.json has no P0/P1 that is `status: "open"`
 *      without `risk_accepted: true`.
 * Anything else - including an unreadable/malformed register - is BLOCKED.
 *
 * Local proof usage:
 *   node .github/scripts/release-gate.cjs --register assessment/risk-register.json \
 *     --net success --tag v1.0.0
 *
 * Exit 0 = RELEASABLE, 1 = BLOCKED. When run in Actions it appends the job
 * summary to $GITHUB_STEP_SUMMARY and `releasable=true|false` to $GITHUB_OUTPUT.
 */

const fs = require('fs');

const BLOCKING_SEVERITIES = new Set(['P0', 'P1']);
const KNOWN_STATUSES = new Set(['open', 'fixed']);

function parseArgs(argv) {
  const args = { register: 'assessment/risk-register.json', net: 'success', tag: 'local' };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--register') args.register = argv[++i];
    else if (argv[i] === '--net') args.net = argv[++i];
    else if (argv[i] === '--tag') args.tag = argv[++i];
    else throw new Error(`unknown argument: ${argv[i]}`);
  }
  return args;
}

function evaluateRelease({ registerPath, netResult }) {
  const blockers = [];
  let register = null;
  try {
    register = JSON.parse(fs.readFileSync(registerPath, 'utf8'));
  } catch (err) {
    blockers.push(`risk register not readable (${registerPath}): ${err.message}`);
  }
  if (register !== null && !Array.isArray(register)) {
    blockers.push(`risk register is not a JSON array (${registerPath})`);
    register = null;
  }
  for (const risk of register || []) {
    if (!risk || typeof risk !== 'object') {
      blockers.push('risk register contains a non-object entry');
      continue;
    }
    const severity = String(risk.severity || '').toUpperCase();
    if (!BLOCKING_SEVERITIES.has(severity)) continue;
    const status = risk.status;
    if (!KNOWN_STATUSES.has(status)) {
      blockers.push(`${risk.id || '?'} ${severity} has unknown status "${status}" (fail closed)`);
    } else if (status === 'open' && risk.risk_accepted !== true) {
      blockers.push(`${risk.id || '?'} ${severity} open without risk_accepted (${risk.file || 'no file'})`);
    }
  }
  const netOk = netResult === 'success';
  return { releasable: netOk && blockers.length === 0, netOk, blockers };
}

function main() {
  const { register, net, tag } = parseArgs(process.argv.slice(2));
  const { releasable, netOk, blockers } = evaluateRelease({ registerPath: register, netResult: net });
  const verdict = releasable ? 'RELEASABLE' : 'BLOCKED';
  const lines = [
    `## Release gate: **${verdict}** - \`${tag}\``,
    '',
    '| Check | Result |',
    '| --- | --- |',
    `| quality net (\`ci.yml\`) | ${netOk ? 'success' : `${net} - NOT GREEN`} |`,
    `| risk register P0/P1 | ${blockers.length === 0 ? 'no unaccepted open P0/P1' : `${blockers.length} blocking`} |`,
  ];
  if (blockers.length > 0) {
    lines.push('', 'Blocking reasons:', ...blockers.map((b) => `- ${b}`));
  }
  const summary = lines.join('\n') + '\n';
  process.stdout.write(summary);
  if (process.env.GITHUB_STEP_SUMMARY) {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
  }
  if (process.env.GITHUB_OUTPUT) {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `releasable=${releasable}\n`);
  }
  process.exit(releasable ? 0 : 1);
}

if (require.main === module) main();

module.exports = { evaluateRelease, BLOCKING_SEVERITIES };
