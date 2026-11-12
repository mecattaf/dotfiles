import { describe, it, beforeEach, afterEach } from 'node:test';
import { strict as assert } from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

// Import the discover function
import { discover } from '../src/lib/discover.mjs';

/**
 * Create a temporary directory for testing
 * @returns {string} path to temporary directory
 */
function createTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'scheduled-test-'));
}

/**
 * Clean up a temporary directory
 * @param {string} dir - directory to clean up
 */
function cleanupTempDir(dir) {
  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch {
    // Ignore cleanup errors
  }
}

/**
 * Set up a test agency structure
 * @param {string} home - home directory
 * @param {string} agencyId - agency ID (e.g., 'master', 'crm')
 * @param {boolean} useSymlink - whether to symlink workflows directory
 * @param {boolean} createErrors - whether to create ownership errors
 */
function setupAgency(home, agencyId, useSymlink = false, createErrors = false) {
  const agencyPath = agencyId === 'master' ? home : path.join(home, agencyId);
  const agencyDir = path.join(agencyPath, '.agency');
  const workflowsDir = path.join(agencyDir, 'scheduled');
  
  // Create directory structure
  fs.mkdirSync(agencyPath, { recursive: true });
  fs.mkdirSync(agencyDir, { recursive: true });

  let actualWorkflowsDir = workflowsDir;
  if (useSymlink) {
    const targetWorkflows = path.join(home, `workflows-target-${agencyId.replace(/\//g, '-')}`);
    fs.mkdirSync(targetWorkflows, { recursive: true });
    fs.symlinkSync(targetWorkflows, workflowsDir);
    actualWorkflowsDir = targetWorkflows;
  } else {
    fs.mkdirSync(workflowsDir, { recursive: true });
  }

  const proposedDir = path.join(actualWorkflowsDir, 'proposed');
  fs.mkdirSync(proposedDir, { recursive: true });
  
  // Create some workflow files
  const workflows = ['workflow1', 'workflow2', 'workflow3'];
  const proposed = ['proposed1', 'proposed2'];
  
  for (const wf of workflows) {
    fs.writeFileSync(path.join(actualWorkflowsDir, `${wf}.jsonc`), JSON.stringify({ id: wf, type: 'jsonc' }));
  }
  
  for (const wf of proposed) {
    fs.writeFileSync(path.join(proposedDir, `${wf}.jsonc`), JSON.stringify({ id: wf, type: 'proposed' }));
  }
  
  // Create invalid workflow file
  fs.writeFileSync(path.join(actualWorkflowsDir, 'invalid!.jsonc'), '{}');
  
  // Set up ownership
  const currentUid = fs.statSync(agencyPath).uid;
  
  // Set up errors if requested
  if (createErrors) {
    // Make directory world-writable to create ownership error
    fs.chmodSync(agencyDir, 0o777);
    fs.chmodSync(actualWorkflowsDir, 0o777);
  }
  
  return { home, agencyId, agencyPath, agencyDir, workflowsDir, proposedDir, uid: currentUid };
}

/**
 * Set up test with nested agencies
 * @param {string} home - home directory
 */
function setupNestedAgencies(home) {
  // Create nested agency structure
  const nested1 = path.join(home, 'parent', 'child', 'grandchild');
  const nested2 = path.join(home, 'other', 'nested');
  
  for (const agencyPath of [nested1, nested2]) {
    const agencyDir = path.join(agencyPath, '.agency');
    const workflowsDir = path.join(agencyDir, 'scheduled');
    
    fs.mkdirSync(agencyPath, { recursive: true });
    fs.mkdirSync(agencyDir, { recursive: true });
    fs.mkdirSync(workflowsDir, { recursive: true });
    
    // Create workflow file
    fs.writeFileSync(path.join(workflowsDir, 'nested-workflow.jsonc'), '{}');
  }
}

/**
 * Set up test with dot directories and node_modules
 * @param {string} home - home directory
 */
function setupExcludedDirectories(home) {
  // Create directories that should be excluded
  const dotDir = path.join(home, '.hidden');
  const nodeModulesDir = path.join(home, 'node_modules');
  
  fs.mkdirSync(dotDir, { recursive: true });
  fs.mkdirSync(nodeModulesDir, { recursive: true });
  
  // Create .agency in excluded directories (should not be discovered)
  const dotAgency = path.join(dotDir, '.agency');
  fs.mkdirSync(dotAgency, { recursive: true });
  const dotWorkflows = path.join(dotAgency, 'scheduled');
  fs.mkdirSync(dotWorkflows, { recursive: true });
  fs.writeFileSync(path.join(dotWorkflows, 'dot-workflow.jsonc'), '{}');
  
  const nodeModulesAgency = path.join(nodeModulesDir, '.agency');
  fs.mkdirSync(nodeModulesAgency, { recursive: true });
  const nodeModulesWorkflows = path.join(nodeModulesAgency, 'scheduled');
  fs.mkdirSync(nodeModulesWorkflows, { recursive: true });
  fs.writeFileSync(path.join(nodeModulesWorkflows, 'node-workflow.jsonc'), '{}');
}

/**
 * Set up test with agency-name error
 * @param {string} home - home directory
 */
function setupAgencyNameError(home) {
  // Create master agency (this is allowed)
  const masterAgency = path.join(home, '.agency');
  fs.mkdirSync(masterAgency, { recursive: true });
  fs.mkdirSync(path.join(masterAgency, 'scheduled'), { recursive: true });
  fs.writeFileSync(path.join(masterAgency, 'scheduled', 'master-workflow.jsonc'), '{}');
  
  // Create master/master directory (should cause agency-name error)
  const masterMaster = path.join(home, 'master', '.agency');
  fs.mkdirSync(masterMaster, { recursive: true });
  fs.mkdirSync(path.join(masterMaster, 'scheduled'), { recursive: true });
  fs.writeFileSync(path.join(masterMaster, 'scheduled', 'invalid-master.jsonc'), '{}');
}

// Test suite
describe('Scheduled Agency Discovery', () => {
  let testHome;
  
  beforeEach(() => {
    testHome = createTempDir();
  });
  
  afterEach(() => {
    if (testHome) {
      cleanupTempDir(testHome);
    }
  });
  
  // Test 1: Basic agency discovery
  it('should discover basic agency structure', async () => {
    const { home, agencyId, uid } = setupAgency(testHome, 'master');
    
    const result = await discover({ home, uid });
    
    // Should discover one agency
    assert.strictEqual(result.agencies.length, 1);
    assert.strictEqual(result.agencies[0].id, 'master');
    assert.strictEqual(result.agencies[0].root, home);
    
    // 3 items; the invalid stem is a problem, and proposed/ beneath scheduled/ is not read
    assert.deepStrictEqual(result.files.map((f) => f.id), ['master:workflow1', 'master:workflow2', 'master:workflow3']);
    for (const file of result.files) {
      assert.strictEqual(file.agency, 'master');
      assert.ok(file.path.includes(`${path.sep}.agency${path.sep}scheduled${path.sep}`));
      assert.strictEqual('proposal' in file, false);
    }
    assert.ok(result.problems.some((p) => p.code === 'stem'));
  });

  it('D1 finds <agency>/.agency/scheduled/*.jsonc and ignores .agency/workflows/ and proposed/', async () => {
    const agencyDir = path.join(testHome, '.agency');
    for (const dir of ['scheduled', 'workflows', path.join('scheduled', 'proposed')]) {
      fs.mkdirSync(path.join(agencyDir, dir), { recursive: true, mode: 0o700 });
    }
    fs.chmodSync(agencyDir, 0o700);
    fs.writeFileSync(path.join(agencyDir, 'scheduled', 'kept.jsonc'), '{}', { mode: 0o600 });
    fs.writeFileSync(path.join(agencyDir, 'workflows', 'old.jsonc'), '{}', { mode: 0o600 });
    fs.writeFileSync(path.join(agencyDir, 'scheduled', 'proposed', 'prop.jsonc'), '{}', { mode: 0o600 });
    fs.writeFileSync(path.join(agencyDir, 'scheduled', '.kept.jsonc.123.tmp'), '{}', { mode: 0o600 });
    const result = await discover({ home: testHome, uid: process.getuid() });
    assert.deepStrictEqual(result.files.map((f) => f.id), ['master:kept']);
  });
  
  // Test 2: Nested agency discovery
  it('should discover nested agency structures', async () => {
    const { uid } = setupAgency(testHome, 'parent');
    setupNestedAgencies(testHome);
    
    const result = await discover({ home: testHome, uid });
    
    // Should discover parent, parent/child/grandchild, and other/nested
    assert.ok(result.agencies.length >= 1);
    
    // Check that we found workflows
    assert.ok(result.files.length >= 3);
  });
  
  // Test 3: Should not discover agencies in excluded directories
  it('should not discover agencies in dot directories or node_modules', async () => {
    const { uid } = setupAgency(testHome, 'master');
    setupExcludedDirectories(testHome);
    
    const result = await discover({ home: testHome, uid });
    
    // Should only discover master agency, not the ones in .hidden or node_modules
    assert.strictEqual(result.agencies.length, 1);
    assert.strictEqual(result.agencies[0].id, 'master');
  });
  
  // Test 4: Should handle symlinks correctly (should not follow)
  it('should not follow symlinks while walking', async () => {
    const { uid } = setupAgency(testHome, 'master');
    
    // Create an agency outside testHome and symlink to it from within testHome
    const outsideDir = createTempDir();
    try {
      setupAgency(outsideDir, 'sub');
      fs.symlinkSync(path.join(outsideDir, 'sub'), path.join(testHome, 'linked-agency'));
      
      const result = await discover({ home: testHome, uid });
      
      // Should discover only master, not linked-agency
      assert.strictEqual(result.agencies.length, 1);
      assert.strictEqual(result.agencies[0].id, 'master');
    } finally {
      cleanupTempDir(outsideDir);
    }
  });
  
  // Test 5: Should detect ownership errors
  it('should detect ownership errors', async () => {
    const { home, agencyId, uid } = setupAgency(testHome, 'master', false, true); // Create errors
    
    const result = await discover({ home, uid });
    
    // Should have ownership problems
    assert.ok(result.problems.some(p => p.code === 'ownership'));
  });
  
  // Test 6: Should detect invalid workflow stems
  it('should detect invalid workflow stems', async () => {
    // Create workflow with invalid stem (already created in setupAgency)
    const { home, uid } = setupAgency(testHome, 'master');
    
    const result = await discover({ home, uid });
    
    // Should have stem problems
    assert.ok(result.problems.some(p => p.code === 'stem'));
  });
  
  // Test 7: Should sort agencies by id then stem
  it('should sort agencies by id then stem', async () => {
    setupAgency(testHome, 'z-agency');
    setupAgency(testHome, 'a-agency');
    const uid = fs.statSync(testHome).uid;
    
    const result = await discover({ home: testHome, uid });
    
    // Check agencies are sorted
    for (let i = 1; i < result.agencies.length; i++) {
      assert.strictEqual(result.agencies[i].id.localeCompare(result.agencies[i-1].id) >= 0, true);
    }
    
    // Check files are sorted by agency then stem
    for (let i = 1; i < result.files.length; i++) {
      const prev = result.files[i-1];
      const curr = result.files[i];
      
      if (prev.agency === curr.agency) {
        assert.strictEqual(curr.stem.localeCompare(prev.stem) >= 0, true);
      } else {
        assert.strictEqual(curr.agency.localeCompare(prev.agency) >= 0, true);
      }
    }
  });
  
  // Test 8: Should handle agency-name error (master/master)
  it('should detect agency-name error for master/master', async () => {
    setupAgencyNameError(testHome);
    const uid = fs.statSync(testHome).uid;
    
    const result = await discover({ home: testHome, uid });
    
    // Should have agency-name error for master/master
    assert.ok(result.problems.some(p => p.code === 'agency-name'));
    // And only ~ is master
    const masterAgencies = result.agencies.filter(a => a.id === 'master');
    assert.strictEqual(masterAgencies.length, 1);
    assert.strictEqual(masterAgencies[0].root, testHome);
  });
  
  // Test 9: Should work with real uid from system
  it('should use correct uid for ownership validation', async () => {
    const { home, agencyId, uid } = setupAgency(testHome, 'master');
    
    const result = await discover({ home, uid });
    
    // Should discover the agency without ownership errors (correct uid)
    assert.strictEqual(result.agencies.length, 1);
    // Should not have ownership problems (assuming correct uid)
    const ownershipProblems = result.problems.filter(p => p.code === 'ownership');
    assert.strictEqual(ownershipProblems.length, 0);
  });

  // Test 10: D/.agency/scheduled may itself be a symlink
  it('should follow a symlinked scheduled directory', async () => {
    const { home, uid } = setupAgency(testHome, 'linked-workflows-agency', true);
    
    const result = await discover({ home, uid });
    
    assert.strictEqual(result.agencies.length, 1);
    assert.strictEqual(result.agencies[0].id, 'linked-workflows-agency');
    
    const agencyFiles = result.files.filter(f => f.agency === 'linked-workflows-agency');
    assert.strictEqual(agencyFiles.length, 3);
  });

  // Test 11: Depth limit - agency roots found down to depth 3, walk down to depth 4
  it('should not discover agency roots deeper than depth 3', async () => {
    const uid = fs.statSync(testHome).uid;

    // depth 1: a
    // depth 2: a/b
    // depth 3: a/b/c (agency root at depth 3 - should be found)
    // depth 4: a/b/c/d (agency root at depth 4 - should NOT be found)
    // depth 5: a/b/c/d/e (should not be visited)
    const depth3Root = path.join(testHome, 'a', 'b', 'c');
    const depth4Root = path.join(depth3Root, 'd');
    const depth5Dir = path.join(depth4Root, 'e');

    fs.mkdirSync(path.join(depth3Root, '.agency', 'scheduled'), { recursive: true });
    fs.writeFileSync(path.join(depth3Root, '.agency', 'scheduled', 'wf3.jsonc'), '{}');

    fs.mkdirSync(path.join(depth4Root, '.agency', 'scheduled'), { recursive: true });
    fs.writeFileSync(path.join(depth4Root, '.agency', 'scheduled', 'wf4.jsonc'), '{}');

    fs.mkdirSync(depth5Dir, { recursive: true });

    const result = await discover({ home: testHome, uid });

    // a/b/c should be discovered
    const agency3 = result.agencies.find(a => a.id === 'a/b/c');
    assert.ok(agency3, 'depth 3 agency should be discovered');

    // a/b/c/d should NOT be discovered
    const agency4 = result.agencies.find(a => a.id === 'a/b/c/d');
    assert.strictEqual(agency4, undefined, 'depth 4 agency should NOT be discovered');

    // visited should contain depth 4 dir but NOT depth 5 dir
    assert.ok(result.visited.includes(depth4Root), 'depth 4 dir should be visited');
    assert.ok(!result.visited.includes(depth5Dir), 'depth 5 dir should not be visited');
  });

  // Test 12: Full claim C2.8 verification
  it('should satisfy claim C2.8', async () => {
    const uid = fs.statSync(testHome).uid;

    // 1. ~/.agency/ exists
    fs.mkdirSync(path.join(testHome, '.agency', 'scheduled'), { recursive: true });
    fs.writeFileSync(path.join(testHome, '.agency', 'scheduled', 'root-wf.jsonc'), '{}');

    // 2. ~/a/b/.agency/workflows/w.jsonc exists
    const abRoot = path.join(testHome, 'a', 'b');
    fs.mkdirSync(path.join(abRoot, '.agency', 'scheduled'), { recursive: true });
    fs.writeFileSync(path.join(abRoot, '.agency', 'scheduled', 'w.jsonc'), '{}');

    // 3. Root deeper than depth 3 (given)
    const deepRoot = path.join(testHome, 'lvl1', 'lvl2', 'lvl3', 'lvl4');
    fs.mkdirSync(path.join(deepRoot, '.agency', 'scheduled'), { recursive: true });
    fs.writeFileSync(path.join(deepRoot, '.agency', 'scheduled', 'deep.jsonc'), '{}');

    // 4. Reachable only through a symlink
    const outside = createTempDir();
    try {
      const outsideAgency = path.join(outside, 'sym-agency');
      fs.mkdirSync(path.join(outsideAgency, '.agency', 'scheduled'), { recursive: true });
      fs.writeFileSync(path.join(outsideAgency, '.agency', 'scheduled', 'sym.jsonc'), '{}');
      fs.symlinkSync(outsideAgency, path.join(testHome, 'sym-link'));

      // 5. Inside a dot-directory
      const dotRoot = path.join(testHome, '.config', 'my-agency');
      fs.mkdirSync(path.join(dotRoot, '.agency', 'scheduled'), { recursive: true });
      fs.writeFileSync(path.join(dotRoot, '.agency', 'scheduled', 'dot.jsonc'), '{}');

      // 6. Inside node_modules
      const nmRoot = path.join(testHome, 'node_modules', 'pkg-agency');
      fs.mkdirSync(path.join(nmRoot, '.agency', 'scheduled'), { recursive: true });
      fs.writeFileSync(path.join(nmRoot, '.agency', 'scheduled', 'nm.jsonc'), '{}');

      // 7. ~/master/.agency/ gives error agency-name
      const masterAgency = path.join(testHome, 'master', '.agency');
      fs.mkdirSync(path.join(masterAgency, 'scheduled'), { recursive: true });
      fs.writeFileSync(path.join(masterAgency, 'scheduled', 'invalid.jsonc'), '{}');

      const result = await discover({ home: testHome, uid });

      // lists agency master and workflow a/b:w
      const master = result.agencies.find(a => a.id === 'master');
      assert.ok(master, 'agency master must be listed');
      assert.strictEqual(master.root, testHome);

      const abAgency = result.agencies.find(a => a.id === 'a/b');
      assert.ok(abAgency, 'agency a/b must be listed');

      const abWorkflow = result.files.find(f => f.id === 'a/b:w');
      assert.ok(abWorkflow, 'workflow a/b:w must be listed');
      assert.strictEqual(abWorkflow.agency, 'a/b');
      assert.strictEqual(abWorkflow.stem, 'w');

      // deeper than depth 3 not listed
      assert.strictEqual(result.agencies.find(a => a.id === 'lvl1/lvl2/lvl3/lvl4'), undefined);

      // reachable only through symlink not listed
      assert.strictEqual(result.agencies.find(a => a.id === 'sym-link'), undefined);

      // dot-directory not listed
      assert.strictEqual(result.agencies.find(a => a.id.includes('.config')), undefined);

      // node_modules not listed
      assert.strictEqual(result.agencies.find(a => a.id.includes('node_modules')), undefined);

      // ~/master/.agency/ gives error agency-name and only agency with id master is ~
      const agencyNameProblem = result.problems.find(p => p.code === 'agency-name');
      assert.ok(agencyNameProblem, 'must report error agency-name');

      const masterAgencies = result.agencies.filter(a => a.id === 'master');
      assert.strictEqual(masterAgencies.length, 1);
      assert.strictEqual(masterAgencies[0].root, testHome);
    } finally {
      cleanupTempDir(outside);
    }
  });
});
