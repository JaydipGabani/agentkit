'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { BRIDGE_PROTOCOL_VERSION, cleanDescriptors, startBridge } = require('./bridge');
const {
  postHook,
  readDescriptors,
  shouldDiscardDescriptor,
} = require('../../scripts/session-title-hook');

test('routes hook input through an authenticated workspace bridge', async (context) => {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'agentkit-title-'));
  context.after(() => fs.promises.rm(directory, { recursive: true, force: true }));

  let received;
  const bridge = await startBridge({
    env: { AGENTKIT_SESSION_TITLE_BRIDGE_DIR: directory },
    workspaceFolders: ['/workspace/repo'],
    handleHook: async (input) => {
      received = input;
      return { status: 'scheduled' };
    },
  });
  context.after(() => bridge.dispose());

  const [descriptor] = await readDescriptors(directory, '/workspace/repo/subdir');
  await postHook(descriptor, {
    session_id: 'session-one',
    prompt: 'review PR #4707',
    cwd: '/workspace/repo/subdir',
  });

  assert.equal(received.session_id, 'session-one');
  assert.equal(descriptor.filePath, bridge.descriptorPath);
});

test('selects the longest matching workspace and rejects ambiguous fallbacks', async (context) => {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'agentkit-title-'));
  context.after(() => fs.promises.rm(directory, { recursive: true, force: true }));

  const descriptors = [
    { protocolVersion: BRIDGE_PROTOCOL_VERSION, port: 1001, token: 'one', updatedAt: Date.now(), workspaceFolders: ['/workspace'] },
    { protocolVersion: BRIDGE_PROTOCOL_VERSION, port: 1002, token: 'two', updatedAt: Date.now(), workspaceFolders: ['/workspace/repo'] },
  ];
  await Promise.all(descriptors.map((descriptor, index) =>
    fs.promises.writeFile(path.join(directory, `${index}.json`), JSON.stringify(descriptor))));

  const [best] = await readDescriptors(directory, '/workspace/repo/subdir');
  assert.equal(best.port, 1002);
  assert.deepEqual(await readDescriptors(directory, '/different/workspace'), []);
});

test('rejects equally specific workspace bridges', async (context) => {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'agentkit-title-'));
  context.after(() => fs.promises.rm(directory, { recursive: true, force: true }));
  for (const [index, port] of [1001, 1002].entries()) {
    await fs.promises.writeFile(path.join(directory, `${index}.json`), JSON.stringify({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      instance: `${process.pid + index + 1}-test`,
      port,
      token: String(port),
      updatedAt: Date.now(),
      workspaceFolders: ['/workspace/repo'],
    }));
  }

  assert.deepEqual(await readDescriptors(directory, '/workspace/repo'), []);
});

test('routes equally specific workspaces to the focused window', async (context) => {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'agentkit-title-'));
  context.after(() => fs.promises.rm(directory, { recursive: true, force: true }));
  const descriptors = [
    { protocolVersion: BRIDGE_PROTOCOL_VERSION, port: 1001, token: 'one', updatedAt: Date.now(), focused: false, focusChangedAt: 1, workspaceFolders: ['/workspace/repo'] },
    { protocolVersion: BRIDGE_PROTOCOL_VERSION, port: 1002, token: 'two', updatedAt: Date.now(), focused: true, focusChangedAt: 2, workspaceFolders: ['/workspace/repo'] },
  ];
  await Promise.all(descriptors.map((descriptor, index) =>
    fs.promises.writeFile(path.join(directory, `${index}.json`), JSON.stringify(descriptor))));

  const [selected] = await readDescriptors(directory, '/workspace/repo');

  assert.equal(selected.port, 1002);
});

test('rejects equally focused windows with identical focus timestamps', async (context) => {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'agentkit-title-'));
  context.after(() => fs.promises.rm(directory, { recursive: true, force: true }));
  for (const [index, port] of [1001, 1002].entries()) {
    await fs.promises.writeFile(path.join(directory, `${index}.json`), JSON.stringify({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      port,
      token: String(port),
      updatedAt: Date.now(),
      focused: true,
      focusChangedAt: 10,
      workspaceFolders: ['/workspace/repo'],
    }));
  }

  assert.deepEqual(await readDescriptors(directory, '/workspace/repo'), []);
});

test('ignores descriptors without a valid freshness timestamp', async (context) => {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'agentkit-title-'));
  context.after(() => fs.promises.rm(directory, { recursive: true, force: true }));
  await fs.promises.writeFile(path.join(directory, 'missing-time.json'), JSON.stringify({
    protocolVersion: BRIDGE_PROTOCOL_VERSION,
    port: 1001,
    token: 'one',
    workspaceFolders: ['/workspace/repo'],
  }));

  assert.deepEqual(await readDescriptors(directory, '/workspace/repo'), []);
});

test('ignores descriptors from an older bridge protocol', async (context) => {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'agentkit-title-'));
  context.after(() => fs.promises.rm(directory, { recursive: true, force: true }));
  await fs.promises.writeFile(path.join(directory, 'v1.json'), JSON.stringify({
    protocolVersion: BRIDGE_PROTOCOL_VERSION - 1,
    port: 1001,
    token: 'one',
    updatedAt: Date.now(),
    workspaceFolders: ['/workspace/repo'],
  }));

  assert.deepEqual(await readDescriptors(directory, '/workspace/repo'), []);
});

test('cleans descriptors owned by the current process', async (context) => {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'agentkit-title-'));
  context.after(() => fs.promises.rm(directory, { recursive: true, force: true }));
  const descriptorPath = path.join(directory, 'current.json');
  await fs.promises.writeFile(descriptorPath, JSON.stringify({
    instance: `${process.pid}-old`,
    updatedAt: Date.now(),
  }));

  await cleanDescriptors(directory);

  await assert.rejects(fs.promises.access(descriptorPath));
});

test('refreshes a live bridge descriptor before it expires', async (context) => {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'agentkit-title-'));
  context.after(() => fs.promises.rm(directory, { recursive: true, force: true }));
  const bridge = await startBridge({
    env: { AGENTKIT_SESSION_TITLE_BRIDGE_DIR: directory },
    workspaceFolders: ['/workspace/repo'],
    handleHook: async () => ({ status: 'scheduled' }),
    heartbeatIntervalMs: 10,
  });
  context.after(() => bridge.dispose());
  const initial = JSON.parse(await fs.promises.readFile(bridge.descriptorPath, 'utf8'));

  const refreshed = await new Promise((resolve, reject) => {
    const deadline = Date.now() + 500;
    const check = async () => {
      try {
        const descriptor = JSON.parse(await fs.promises.readFile(bridge.descriptorPath, 'utf8'));
        if (descriptor.updatedAt > initial.updatedAt) {
          resolve(descriptor);
          return;
        }
      } catch (error) {
        reject(error);
        return;
      }
      if (Date.now() >= deadline) {
        reject(new Error('descriptor heartbeat did not refresh'));
        return;
      }
      setTimeout(check, 10);
    };
    setTimeout(check, 10);
  });

  assert.equal(refreshed.workspaceFolders[0], '/workspace/repo');
});

test('times out without discarding a bridge that may still be live', async (context) => {
  const server = http.createServer(() => {});
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  context.after(() => server.close());
  const address = server.address();

  await assert.rejects(
    postHook({ port: address.port, token: 'test' }, { prompt: 'review PR #1' }, 25),
    (error) => error.code === 'ETIMEDOUT' && !shouldDiscardDescriptor(error),
  );
});