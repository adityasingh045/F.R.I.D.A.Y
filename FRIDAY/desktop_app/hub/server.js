// TARGET: Node.js 20+ | ws 8.x | http2 native
// JARVIS HUB: Central relay, auth, and encryption gateway

import { WebSocketServer, WebSocket } from 'ws';
import http2 from 'http2';
import fs from 'fs';
import crypto from 'crypto';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const multicastDns = require('multicast-dns');

// ── CONFIG ─────────────────────────────────────────────────────────────────
const CONFIG = {
  WS_PORT: 8765,
  HTTP2_PORT: 8766,
  SERVICE_NAME: 'multi-screen-collaborate',
  AES_KEY: process.env.SESSION_KEY || crypto.randomBytes(32).toString('hex'),
  MAX_CLIENTS: 8,
};

// ── AES-256-GCM ENCRYPTION ─────────────────────────────────────────────────
const encrypt = (payload) => {
  const iv = crypto.randomBytes(12);
  const key = Buffer.from(CONFIG.AES_KEY, 'hex');
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([
    cipher.update(JSON.stringify(payload), 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return {
    iv: iv.toString('base64'),
    data: encrypted.toString('base64'),
    tag: tag.toString('base64'),
  };
};

const decrypt = (envelope) => {
  try {
    const key = Buffer.from(CONFIG.AES_KEY, 'hex');
    const iv = Buffer.from(envelope.iv, 'base64');
    const tag = Buffer.from(envelope.tag, 'base64');
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);
    const decrypted = Buffer.concat([
      decipher.update(Buffer.from(envelope.data, 'base64')),
      decipher.final(),
    ]);
    return JSON.parse(decrypted.toString('utf8'));
  } catch (err) {
    console.error('[JARVIS-HUB] Decryption failure:', err.message);
    return null;
  }
};

// ── CLIENT REGISTRY ────────────────────────────────────────────────────────
const clients = new Map(); // deviceId → { ws, type, name, authorized }

// ── WEBSOCKET HUB ──────────────────────────────────────────────────────────
const wss = new WebSocketServer({ port: CONFIG.WS_PORT });

wss.on('connection', (ws, req) => {
  const deviceId = crypto.randomUUID();
  clients.set(deviceId, { ws, type: null, name: null, authorized: false });
  console.log(`[JARVIS-HUB] Client connected: ${deviceId} | IP: ${req.socket.remoteAddress}`);

  // Send handshake challenge
  ws.send(JSON.stringify({
    type: 'HANDSHAKE',
    deviceId,
    challenge: crypto.randomBytes(16).toString('hex'),
  }));

  ws.on('message', (raw) => {
    try {
      const envelope = JSON.parse(raw);
      const message = decrypt(envelope);
      if (!message) return ws.close(4001, 'Decryption failed');

      handleMessage(deviceId, message, ws);
    } catch (err) {
      console.error(`[JARVIS-HUB] Message parse error: ${err.message}`);
    }
  });

  ws.on('close', () => {
    clients.delete(deviceId);
    broadcast({ type: 'DEVICE_DISCONNECTED', deviceId }, deviceId);
    console.log(`[JARVIS-HUB] Client disconnected: ${deviceId}`);
  });

  ws.on('error', (err) => {
    console.error(`[JARVIS-HUB] WS error on ${deviceId}: ${err.message}`);
  });
});

// ── MESSAGE ROUTER ─────────────────────────────────────────────────────────
const handleMessage = (senderId, message, ws) => {
  const client = clients.get(senderId);

  switch (message.type) {

    case 'AUTH':
      // Validate shared session key hash
      const keyHash = crypto
        .createHash('sha256')
        .update(CONFIG.AES_KEY)
        .digest('hex');
      if (message.keyHash === keyHash) {
        client.authorized = true;
        client.type = message.deviceType; // 'android' | 'desktop'
        client.name = message.deviceName;
        ws.send(JSON.stringify(encrypt({ type: 'AUTH_OK', deviceId: senderId })));
        broadcast({ type: 'DEVICE_CONNECTED', deviceId: senderId, name: client.name }, senderId);
        console.log(`[JARVIS-HUB] Auth SUCCESS: ${client.name} (${client.type})`);
      } else {
        ws.send(JSON.stringify(encrypt({ type: 'AUTH_FAIL' })));
        ws.close(4003, 'Unauthorized');
      }
      break;

    case 'SCREEN_FRAME':
    case 'INPUT_EVENT':
    case 'CLIPBOARD':
    case 'DRAG_PAYLOAD':
    case 'VOICE_CMD':
      if (!client.authorized) return;
      // Route to specific target or broadcast
      if (message.targetId && clients.has(message.targetId)) {
        const target = clients.get(message.targetId);
        safeSend(target.ws, encrypt(message));
      } else {
        broadcast(message, senderId);
      }
      break;

    case 'FILE_TRANSFER_INIT':
      if (!client.authorized) return;
      // Returns HTTP/2 upload token
      const token = crypto.randomBytes(16).toString('hex');
      fileTokens.set(token, { senderId, targetId: message.targetId, filename: message.filename });
      ws.send(JSON.stringify(encrypt({ type: 'FILE_TOKEN', token, port: CONFIG.HTTP2_PORT })));
      break;

    default:
      console.warn(`[JARVIS-HUB] Unknown message type: ${message.type}`);
  }
};

// ── BROADCAST UTILITY ──────────────────────────────────────────────────────
const broadcast = (message, excludeId = null) => {
  const payload = JSON.stringify(encrypt(message));
  clients.forEach((client, id) => {
    if (id !== excludeId && client.authorized && client.ws.readyState === WebSocket.OPEN) {
      safeSend(client.ws, payload);
    }
  });
};

const safeSend = (ws, data) => {
  try {
    if (ws.readyState === WebSocket.OPEN) ws.send(data);
  } catch (err) {
    console.error('[JARVIS-HUB] Send error:', err.message);
  }
};

// ── HTTP/2 FILE PROXY ──────────────────────────────────────────────────────
const fileTokens = new Map();

const h2Server = http2.createServer();
h2Server.on('stream', (stream, headers) => {
  const token = headers['x-file-token'];
  if (!fileTokens.has(token)) {
    stream.respond({ ':status': 403 });
    return stream.end();
  }

  const meta = fileTokens.get(token);
  const savePath = `./uploads/${Date.now()}_${meta.filename}`;
  const writeStream = fs.createWriteStream(savePath);

  stream.pipe(writeStream);
  writeStream.on('finish', () => {
    fileTokens.delete(token);
    // Notify target device
    const target = clients.get(meta.targetId);
    if (target) safeSend(target.ws, JSON.stringify(encrypt({
      type: 'FILE_READY',
      filename: meta.filename,
      path: savePath,
    })));
    stream.respond({ ':status': 200 });
    stream.end();
    console.log(`[JARVIS-HUB] File received: ${savePath}`);
  });
});

h2Server.listen(CONFIG.HTTP2_PORT, () => {
  console.log(`[JARVIS-HUB] HTTP/2 File Proxy → port ${CONFIG.HTTP2_PORT}`);
});

// ── mDNS BROADCAST ─────────────────────────────────────────────────────────
const mdns = multicastDns();
mdns.on('query', (query) => {
  query.questions.forEach((q) => {
    if (q.name === CONFIG.SERVICE_NAME) {
      mdns.respond({
        answers: [{
          name: CONFIG.SERVICE_NAME,
          type: 'A',
          data: '0.0.0.0', // Replaced by actual IP at runtime
        }, {
          name: CONFIG.SERVICE_NAME,
          type: 'SRV',
          data: { port: CONFIG.WS_PORT, target: CONFIG.SERVICE_NAME },
        }],
      });
    }
  });
});

console.log(`
╔══════════════════════════════════════════╗
║     JARVIS HUB — ONLINE                 ║
║  WebSocket  → ws://0.0.0.0:${CONFIG.WS_PORT}       ║
║  HTTP/2     → https://0.0.0.0:${CONFIG.HTTP2_PORT}     ║
║  mDNS       → ${CONFIG.SERVICE_NAME}  ║
╚══════════════════════════════════════════╝
`);