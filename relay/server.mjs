import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8787);
const CALL_FREEZE_GRACE_MS = Number(process.env.CALL_FREEZE_GRACE_MS || 25000);
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

/**
 * In-memory rooms store (RAM only — voice chunks are NEVER written to disk).
 * code -> {
 *   code: string,
 *   hostId: string,
 *   isPublic: boolean,
 *   biome: number,
 *   members: Map<playerId, {
 *     playerId: string,
 *     callsign: string,
 *     frozen: boolean,
 *     send: ((jsonStr: string) => void) | null,
 *     graceTimer: ReturnType<typeof setTimeout> | null
 *   }>
 * }
 */
const rooms = new Map();

function generateRoomCode() {
  for (let attempt = 0; attempt < 100; attempt++) {
    let code = "";
    for (let i = 0; i < 4; i++) {
      code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    }
    if (!rooms.has(code)) return code;
  }
  return "E7" + Math.floor(10 + Math.random() * 89);
}

function broadcastToRoom(room, payloadObj, excludePlayerId = "") {
  const raw = JSON.stringify(payloadObj);
  for (const [pid, member] of room.members.entries()) {
    if (pid !== excludePlayerId && member.send) {
      try {
        member.send(raw);
      } catch {
        // Ignore broken pipe; disconnect handler will manage grace period
      }
    }
  }
}

function serializeMembers(room) {
  const list = [];
  for (const m of room.members.values()) {
    list.push({
      player_id: m.playerId,
      callsign: m.callsign,
      frozen: Boolean(m.frozen),
    });
  }
  return list;
}

function removeMemberPermanently(room, playerId) {
  const member = room.members.get(playerId);
  if (!member) return;
  if (member.graceTimer) {
    clearTimeout(member.graceTimer);
    member.graceTimer = null;
  }
  room.members.delete(playerId);

  if (room.members.size === 0) {
    rooms.delete(room.code);
    return;
  }

  broadcastToRoom(room, {
    t: "peer_left",
    player_id: playerId,
  });

  // Seamless Host Migration if the host left or timed out
  if (room.hostId === playerId) {
    let nextHost = null;
    for (const candidate of room.members.values()) {
      if (!candidate.frozen) {
        nextHost = candidate;
        break;
      }
    }
    if (!nextHost) {
      nextHost = room.members.values().next().value;
    }
    if (nextHost) {
      room.hostId = nextHost.playerId;
      broadcastToRoom(room, {
        t: "host_migrated",
        host_id: nextHost.playerId,
        host_callsign: nextHost.callsign,
      });
    }
  }
}

export function handleClientPacket(connState, msg, sendFn) {
  if (!msg || typeof msg !== "object") return;
  const type = String(msg.t || "");
  const playerId = String(msg.player_id || connState.playerId || "").trim();
  if (playerId) connState.playerId = playerId;

  switch (type) {
    case "ping": {
      sendFn(JSON.stringify({ t: "pong", ts: Date.now() }));
      break;
    }

    case "list_rooms": {
      const openRooms = [];
      for (const r of rooms.values()) {
        if (r.isPublic && r.members.size > 0 && r.members.size < 4) {
          const hostMember = r.members.get(r.hostId);
          openRooms.push({
            code: r.code,
            host: hostMember ? hostMember.callsign : "BRIGADE",
            count: r.members.size,
            max: 4,
            biome: r.biome,
          });
        }
      }
      sendFn(JSON.stringify({ t: "rooms_list", rooms: openRooms }));
      break;
    }

    case "create_room": {
      if (!playerId) return;
      if (connState.roomCode && rooms.has(connState.roomCode)) {
        removeMemberPermanently(rooms.get(connState.roomCode), playerId);
      }
      const code = generateRoomCode();
      const callsign = String(msg.callsign || "LISTENER").slice(0, 16);
      const room = {
        code,
        hostId: playerId,
        isPublic: msg.public !== false,
        biome: Number(msg.biome || 1),
        members: new Map(),
      };
      room.members.set(playerId, {
        playerId,
        callsign,
        frozen: false,
        send: sendFn,
        graceTimer: null,
      });
      rooms.set(code, room);
      connState.roomCode = code;

      sendFn(
        JSON.stringify({
          t: "room_joined",
          code: room.code,
          host_id: room.hostId,
          members: serializeMembers(room),
        })
      );
      break;
    }

    case "join_room":
    case "rejoin_room": {
      if (!playerId) return;
      const code = String(msg.code || "").trim().toUpperCase();
      const room = rooms.get(code);
      if (!room) {
        sendFn(JSON.stringify({ t: "error", reason: "ROOM_NOT_FOUND" }));
        return;
      }
      const existing = room.members.get(playerId);
      if (!existing && room.members.size >= 4) {
        sendFn(JSON.stringify({ t: "error", reason: "ROOM_FULL" }));
        return;
      }

      const callsign = String(msg.callsign || (existing ? existing.callsign : "LISTENER")).slice(0, 16);
      if (existing) {
        if (existing.graceTimer) {
          clearTimeout(existing.graceTimer);
          existing.graceTimer = null;
        }
        existing.callsign = callsign;
        existing.frozen = false;
        existing.send = sendFn;
        broadcastToRoom(
          room,
          { t: "peer_frozen", player_id: playerId, frozen: false },
          playerId
        );
      } else {
        room.members.set(playerId, {
          playerId,
          callsign,
          frozen: false,
          send: sendFn,
          graceTimer: null,
        });
        broadcastToRoom(
          room,
          { t: "peer_joined", player_id: playerId, callsign },
          playerId
        );
      }

      connState.roomCode = code;
      sendFn(
        JSON.stringify({
          t: "room_joined",
          code: room.code,
          host_id: room.hostId,
          members: serializeMembers(room),
        })
      );
      break;
    }

    case "leave_room": {
      if (!connState.roomCode) return;
      const room = rooms.get(connState.roomCode);
      if (room && connState.playerId) {
        removeMemberPermanently(room, connState.playerId);
      }
      connState.roomCode = "";
      break;
    }

    case "player_state": {
      if (!connState.roomCode) return;
      const room = rooms.get(connState.roomCode);
      if (!room) return;
      broadcastToRoom(
        room,
        {
          t: "player_state",
          player_id: playerId,
          state: msg.state || {},
        },
        playerId
      );
      break;
    }

    case "voice": {
      // Transit-only RAM voice relay (8kHz 8-bit mono base64). Never stored to disk.
      if (!connState.roomCode) return;
      const room = rooms.get(connState.roomCode);
      if (!room) return;
      broadcastToRoom(
        room,
        {
          t: "voice",
          player_id: playerId,
          lvl: Number(msg.lvl || 0.5),
          b64: String(msg.b64 || ""),
        },
        playerId
      );
      break;
    }

    case "game_event": {
      if (!connState.roomCode) return;
      const room = rooms.get(connState.roomCode);
      if (!room) return;
      const ev = String(msg.ev || "");
      const data = msg.data && typeof msg.data === "object" ? msg.data : {};
      if (ev === "call_freeze") {
        const m = room.members.get(playerId);
        if (m) m.frozen = Boolean(data.frozen);
      }
      broadcastToRoom(
        room,
        {
          t: "game_event",
          player_id: playerId,
          ev,
          data,
        },
        playerId
      );
      break;
    }
  }
}

export function handleClientDisconnect(connState) {
  if (!connState.roomCode || !connState.playerId) return;
  const room = rooms.get(connState.roomCode);
  if (!room) return;
  const member = room.members.get(connState.playerId);
  if (!member) return;

  member.send = null;
  member.frozen = true;
  broadcastToRoom(
    room,
    {
      t: "peer_frozen",
      player_id: connState.playerId,
      frozen: true,
    },
    connState.playerId
  );

  if (member.graceTimer) clearTimeout(member.graceTimer);
  const pid = connState.playerId;
  member.graceTimer = setTimeout(() => {
    removeMemberPermanently(room, pid);
  }, CALL_FREEZE_GRACE_MS);
}

// ---------------------------------------------------------------------------
// Minimal RFC 6455 WebSocket Frame Encoder / Decoder for Zero-Dependency Node
// ---------------------------------------------------------------------------
function encodeWsTextFrame(text) {
  const payload = Buffer.from(text, "utf8");
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x81; // FIN + text frame
    header[1] = len;
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payload]);
}

function attachRawWebSocket(socket, initialHead = null) {
  const connState = { playerId: "", roomCode: "" };
  let buffer = Buffer.alloc(0);

  const sendFn = (jsonStr) => {
    if (!socket.destroyed && socket.writable) {
      socket.write(encodeWsTextFrame(jsonStr));
    }
  };

  const onChunk = (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (buffer.length >= 2) {
      const firstByte = buffer[0];
      const secondByte = buffer[1];
      const opcode = firstByte & 0x0f;
      const isMasked = (secondByte & 0x80) !== 0;
      let payloadLen = secondByte & 0x7f;
      let offset = 2;

      if (payloadLen === 126) {
        if (buffer.length < 4) return;
        payloadLen = buffer.readUInt16BE(2);
        offset = 4;
      } else if (payloadLen === 127) {
        if (buffer.length < 10) return;
        payloadLen = Number(buffer.readBigUInt64BE(2));
        offset = 10;
      }

      const maskLen = isMasked ? 4 : 0;
      if (buffer.length < offset + maskLen + payloadLen) return;

      let maskKey = null;
      if (isMasked) {
        maskKey = buffer.subarray(offset, offset + 4);
        offset += 4;
      }

      const payload = Buffer.from(buffer.subarray(offset, offset + payloadLen));
      buffer = buffer.subarray(offset + payloadLen);

      if (isMasked && maskKey) {
        for (let i = 0; i < payload.length; i++) {
          payload[i] ^= maskKey[i & 3];
        }
      }

      if (opcode === 0x08) {
        // Close frame
        socket.end();
        return;
      } else if (opcode === 0x09) {
        // Ping -> Pong (RFC 6455: echo identical payload)
        const plen = Math.min(payload.length, 125);
        const pong = Buffer.concat([Buffer.from([0x8a, plen]), payload.subarray(0, plen)]);
        if (!socket.destroyed) socket.write(pong);
      } else if (opcode === 0x01 || opcode === 0x02) {
        try {
          const text = payload.toString("utf8");
          const parsed = JSON.parse(text);
          handleClientPacket(connState, parsed, sendFn);
        } catch {
          // Ignore malformed JSON packet
        }
      }
    }
  };

  socket.on("data", onChunk);
  socket.on("close", () => handleClientDisconnect(connState));
  socket.on("error", () => handleClientDisconnect(connState));

  if (initialHead && initialHead.length > 0) {
    onChunk(initialHead);
  }
}

export function startRelayServer(port = PORT) {
  const privacyPath = path.resolve(__dirname, "../game/privacy_policy.html");

  const server = http.createServer((req, res) => {
    if (req.url === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          status: "ok",
          service: "dead-decibel-relay",
          active_rooms: rooms.size,
        })
      );
      return;
    }
    if (req.url === "/privacy") {
      if (fs.existsSync(privacyPath)) {
        res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        res.end(fs.readFileSync(privacyPath, "utf8"));
      } else {
        res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
        res.end("DEAD DECIBEL — Microphone audio is processed in RAM only.");
      }
      return;
    }
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("DEAD DECIBEL // Co-op & Proximity Voice Relay Online\n");
  });

  server.on("upgrade", (req, socket, head) => {
    const key = req.headers["sec-websocket-key"];
    if (!key) {
      socket.destroy();
      return;
    }
    const accept = crypto
      .createHash("sha1")
      .update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
      .digest("base64");

    socket.write(
      [
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
        `Sec-WebSocket-Accept: ${accept}`,
        "\r\n",
      ].join("\r\n")
    );
    attachRawWebSocket(socket, head);
  });

  return new Promise((resolve) => {
    server.listen(port, "0.0.0.0", () => {
      const addr = server.address();
      const actualPort = typeof addr === "object" && addr ? addr.port : port;
      console.log(`[DEAD DECIBEL RELAY] Listening on ws://0.0.0.0:${actualPort}`);
      resolve({ server, port: actualPort, rooms });
    });
  });
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  startRelayServer(PORT);
}
