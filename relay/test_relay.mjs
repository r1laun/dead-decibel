import assert from "node:assert/strict";
import { handleClientPacket, handleClientDisconnect, startRelayServer } from "./server.mjs";

async function runTests() {
  console.log("--- Running ECHO-7 WebSocket Relay Automated Tests ---");

  // 1. Unit-test packet state machine: Create, List, Join, Voice, Call-Freeze, Rejoin, Host Migration
  const hostOut = [];
  const peerOut = [];
  const hostConn = { playerId: "", roomCode: "" };
  const peerConn = { playerId: "", roomCode: "" };

  handleClientPacket(
    hostConn,
    { t: "create_room", player_id: "P_HOST", callsign: "ALPHA", public: true, biome: 2 },
    (str) => hostOut.push(JSON.parse(str))
  );

  assert.equal(hostOut.length, 1);
  assert.equal(hostOut[0].t, "room_joined");
  assert.equal(hostOut[0].code.length, 4);
  const roomCode = hostOut[0].code;
  console.log("[PASS] 4-letter Room Code created:", roomCode);

  // List open lobbies
  const listOut = [];
  handleClientPacket(
    { playerId: "P_SEARCH", roomCode: "" },
    { t: "list_rooms", player_id: "P_SEARCH" },
    (str) => listOut.push(JSON.parse(str))
  );
  assert.equal(listOut[0].t, "rooms_list");
  assert.ok(listOut[0].rooms.some((r) => r.code === roomCode && r.biome === 2));
  console.log("[PASS] Open Lobbies listing returned created room");

  // Second player joins room by 4-letter code
  handleClientPacket(
    peerConn,
    { t: "join_room", code: roomCode, player_id: "P_CREW", callsign: "BRAVO" },
    (str) => peerOut.push(JSON.parse(str))
  );

  assert.equal(peerOut[0].t, "room_joined");
  assert.equal(peerOut[0].members.length, 2);
  assert.equal(hostOut.at(-1).t, "peer_joined");
  assert.equal(hostOut.at(-1).callsign, "BRAVO");
  console.log("[PASS] Second player joined by code & notified host");

  // 3D Proximity Voice packet relay
  handleClientPacket(
    peerConn,
    { t: "voice", player_id: "P_CREW", lvl: 0.72, b64: "gICAgA==" },
    (str) => peerOut.push(JSON.parse(str))
  );
  assert.equal(hostOut.at(-1).t, "voice");
  assert.equal(hostOut.at(-1).player_id, "P_CREW");
  assert.equal(hostOut.at(-1).b64, "gICAgA==");
  console.log("[PASS] RAM-only 3D Proximity Voice packet relayed to squad");

  // Simulate unexpected phone call / network drop on P_CREW -> Call-Freeze Stasis
  handleClientDisconnect(peerConn);
  assert.equal(hostOut.at(-1).t, "peer_frozen");
  assert.equal(hostOut.at(-1).player_id, "P_CREW");
  assert.equal(hostOut.at(-1).frozen, true);
  console.log("[PASS] Unexpected drop triggered Call-Freeze stasis for squad");

  // Simulate P_CREW rejoining within 25s grace window
  handleClientPacket(
    peerConn,
    { t: "rejoin_room", code: roomCode, player_id: "P_CREW", callsign: "BRAVO" },
    (str) => peerOut.push(JSON.parse(str))
  );
  assert.equal(hostOut.at(-1).t, "peer_frozen");
  assert.equal(hostOut.at(-1).frozen, false);
  console.log("[PASS] Rejoin within 25s grace window unfroze player seamlessly");

  // Simulate Host leaving -> Automatic Host Migration to P_CREW
  handleClientPacket(
    hostConn,
    { t: "leave_room", player_id: "P_HOST" },
    (str) => hostOut.push(JSON.parse(str))
  );
  assert.equal(peerOut.at(-1).t, "host_migrated");
  assert.equal(peerOut.at(-1).host_id, "P_CREW");
  assert.equal(peerOut.at(-1).host_callsign, "BRAVO");
  console.log("[PASS] Host departure triggered automatic Host Migration to BRAVO");

  // Clean up room
  handleClientPacket(peerConn, { t: "leave_room", player_id: "P_CREW" }, () => {});

  // 2. Test HTTP Health & Privacy endpoints
  const srv = await startRelayServer(0);
  const resHealth = await fetch(`http://127.0.0.1:${srv.port}/health`);
  const healthJson = await resHealth.json();
  assert.equal(healthJson.status, "ok");
  const resPriv = await fetch(`http://127.0.0.1:${srv.port}/privacy`);
  const privHtml = await resPriv.text();
  assert.ok(privHtml.includes("RECORD_AUDIO"));
  srv.server.close();
  console.log("[PASS] HTTP /health and /privacy endpoints verified");
  console.log("=== ALL RELAY SERVER TESTS PASSED ===");
}

runTests().catch((err) => {
  console.error(err);
  process.exit(1);
});
