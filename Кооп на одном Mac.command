#!/bin/bash
# МЁРТВЫЙ ДЕЦИБЕЛ (v4.1) / DEAD DECIBEL — кооператив в двух окнах на одном Mac.
# Окно 1: ведущий (создаёт канал). Окно 2: напарник (входит по коду).
cd "$(dirname "$0")" || exit 1
PORT=8787
RELAY_PID=""
cleanup() { [ -n "$RELAY_PID" ] && kill "$RELAY_PID" 2>/dev/null; }
trap cleanup EXIT

if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "Ретранслятор уже работает на порту $PORT — использую его."
else
  node relay/server.mjs &
  RELAY_PID=$!
  sleep 0.8
fi

echo
echo "Окно 1 (ведущий):  меню «Кооператив» → «Создать канал» → продиктуйте код."
echo "Окно 2 (напарник): меню «Кооператив» → «Войти по коду» → код из окна 1."
echo "Микрофон в обоих окнах выключен — вы и так в одной комнате :)"
echo "Закройте оба окна игры, чтобы остановить ретранслятор."
echo

ECHO7_RELAY_URL="ws://127.0.0.1:$PORT" ECHO7_MIC_MODE=2 godot --path game &
G1=$!
ECHO7_RELAY_URL="ws://127.0.0.1:$PORT" ECHO7_PLAYER_ID="SRV-LOCAL2" ECHO7_CALLSIGN="НАПАРНИК" ECHO7_MIC_MODE=2 godot --path game &
G2=$!
wait $G1 $G2
