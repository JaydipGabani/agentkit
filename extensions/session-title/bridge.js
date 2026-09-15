'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const MAX_REQUEST_BYTES = 1024 * 1024;
const MAX_DESCRIPTOR_AGE_MS = 5 * 60 * 1000;
const DEFAULT_HEARTBEAT_INTERVAL_MS = 60 * 1000;
const BRIDGE_PROTOCOL_VERSION = 2;

function bridgeDirectory(env = process.env) {
  return env.AGENTKIT_SESSION_TITLE_BRIDGE_DIR
    || path.join(os.homedir(), '.cache', 'agentkit', 'session-title-bridges');
}

function readRequest(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;

    request.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_REQUEST_BYTES) {
        reject(new Error('request is too large'));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    request.on('error', reject);
  });
}

function tokenMatches(actual, expected) {
  const left = Buffer.from(String(actual ?? ''));
  const right = Buffer.from(expected);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

async function writeDescriptor(filePath, descriptor) {
  const temporary = `${filePath}.tmp`;
  await fs.promises.writeFile(temporary, `${JSON.stringify(descriptor)}\n`, { mode: 0o600 });
  await fs.promises.rename(temporary, filePath);
}

function processIsRunning(processId) {
  try {
    process.kill(processId, 0);
    return true;
  } catch (error) {
    return error?.code !== 'ESRCH';
  }
}

async function cleanDescriptors(directory, currentProcessId = process.pid) {
  let names;
  try {
    names = await fs.promises.readdir(directory);
  } catch {
    return;
  }

  await Promise.all(names.filter((name) => name.endsWith('.json')).map(async (name) => {
    const filePath = path.join(directory, name);
    try {
      const descriptor = JSON.parse(await fs.promises.readFile(filePath, 'utf8'));
      const processId = Number.parseInt(String(descriptor.instance ?? '').split('-')[0], 10);
      const expired = Date.now() - Number(descriptor.updatedAt ?? 0) > MAX_DESCRIPTOR_AGE_MS;
        if (!Number.isInteger(processId)
          || processId === currentProcessId
          || expired
          || !processIsRunning(processId)) {
        await fs.promises.unlink(filePath);
      }
    } catch {
      await fs.promises.unlink(filePath).catch(() => {});
    }
  }));
}

async function startBridge({
  handleHook,
  workspaceFolders = [],
  log = () => {},
  env = process.env,
  heartbeatIntervalMs = DEFAULT_HEARTBEAT_INTERVAL_MS,
  focused = true,
}) {
  const directory = bridgeDirectory(env);
  await fs.promises.mkdir(directory, { recursive: true, mode: 0o700 });
  await fs.promises.chmod(directory, 0o700);
  await cleanDescriptors(directory);

  const token = crypto.randomBytes(32).toString('hex');
  const instance = `${process.pid}-${crypto.randomBytes(6).toString('hex')}`;
  const descriptorPath = path.join(directory, `${instance}.json`);
  let folders = workspaceFolders;
  let disposed = false;
  let refreshQueue = Promise.resolve();
  let windowFocused = focused;
  let focusChangedAt = Date.now();

  const server = http.createServer(async (request, response) => {
    if (request.method !== 'POST' || request.url !== '/hook') {
      response.writeHead(404).end();
      return;
    }
    if (!tokenMatches(request.headers['x-agentkit-token'], token)) {
      response.writeHead(403).end();
      return;
    }

    try {
      const input = JSON.parse(await readRequest(request));
      const result = await handleHook(input);
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify(result));
    } catch (error) {
      log(`Bridge request failed: ${error instanceof Error ? error.message : String(error)}`);
      response.writeHead(400, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ status: 'error' }));
    }
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });

  const address = server.address();
  if (!address || typeof address === 'string') {
    server.close();
    throw new Error('bridge did not receive a TCP port');
  }

  const refreshDescriptor = () => {
    const refresh = async () => {
      if (disposed) {
        return;
      }
      await writeDescriptor(descriptorPath, {
        protocolVersion: BRIDGE_PROTOCOL_VERSION,
        instance,
        port: address.port,
        token,
        updatedAt: Date.now(),
        focused: windowFocused,
        focusChangedAt,
        workspaceFolders: folders,
      });
    };
    refreshQueue = refreshQueue.then(refresh, refresh);
    return refreshQueue;
  };
  await refreshDescriptor();
  const heartbeat = setInterval(() => {
    refreshDescriptor().catch((error) => log(`Bridge heartbeat failed: ${error.message}`));
  }, heartbeatIntervalMs);
  heartbeat.unref?.();

  return {
    descriptorPath,
    async updateWorkspaceFolders(nextFolders) {
      folders = nextFolders;
      await refreshDescriptor();
    },
    async updateWindowFocus(nextFocused) {
      windowFocused = Boolean(nextFocused);
      focusChangedAt = Date.now();
      await refreshDescriptor();
    },
    dispose() {
      disposed = true;
      clearInterval(heartbeat);
      server.close();
      void refreshQueue
        .catch(() => {})
        .then(() => fs.promises.unlink(descriptorPath).catch(() => {}));
    },
  };
}

module.exports = {
  BRIDGE_PROTOCOL_VERSION,
  bridgeDirectory,
  cleanDescriptors,
  DEFAULT_HEARTBEAT_INTERVAL_MS,
  startBridge,
};