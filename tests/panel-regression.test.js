const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const call = method => execFileSync('omarchy-shell', ['bone.timekeeper.diagnostics', method], { encoding: 'utf8', timeout: 5000 }).trim();
test('real QML controls, first-open layout, reactive bar readouts, and laps', {
  skip: process.env.TIMEKEEPER_RUNTIME_TESTS !== '1' ? 'Set TIMEKEEPER_RUNTIME_TESTS=1 with the matching plugin installed in a running shell' : false,
  timeout: 45000,
}, async () => {
  assert.equal(call('runChecks'), 'started');
  for (let attempt = 0; attempt < 100; attempt++) {
    await new Promise(resolve => setTimeout(resolve, 250));
    const result = JSON.parse(call('inspect')).checks;
    if (result.status === 'running') continue;
    assert.equal(result.status, 'passed', JSON.stringify(result));
    console.log(`${result.assertions} runtime QML assertions passed`);
    return;
  }
  assert.fail('Runtime suite did not finish');
});
