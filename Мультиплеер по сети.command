#!/bin/bash
# МЁРТВЫЙ ДЕЦИБЕЛ (v4.1) / DEAD DECIBEL — мультиплеер по сети (одна Wi-Fi сеть или интернет).
# Поднимает ретранслятор, при наличии cloudflared — публичный wss-туннель,
# копирует адрес в буфер обмена и открывает окно ведущего.
cd "$(dirname "$0")" || exit 1
PORT=8787
RELAY_PID=""
TUNNEL_PID=""
cleanup() {
  [ -n "$TUNNEL_PID" ] && kill "$TUNNEL_PID" 2>/dev/null
  [ -n "$RELAY_PID" ] && kill "$RELAY_PID" 2>/dev/null
}
trap cleanup EXIT

if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "Ретранслятор уже работает на порту $PORT — использую его."
else
  node relay/server.mjs &
  RELAY_PID=$!
  sleep 0.8
fi

WSS=""
if command -v cloudflared >/dev/null 2>&1; then
  echo "Поднимаю интернет-туннель Cloudflare (без аккаунта)..."
  cloudflared tunnel --url "http://127.0.0.1:$PORT" --no-autoupdate > /tmp/echo7_tunnel.log 2>&1 &
  TUNNEL_PID=$!
  U=""
  for i in $(seq 1 60); do
    U=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/echo7_tunnel.log | head -n1)
    [ -n "$U" ] && break
    sleep 0.5
  done
  if [ -n "$U" ]; then
    for i in $(seq 1 60); do
      curl -sf "$U/health" >/dev/null 2>&1 && break
      sleep 0.5
    done
    WSS="wss://${U#https://}"
  fi
else
  echo "cloudflared не найден. Для игры через интернет: brew install cloudflared"
fi

LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
echo
echo "================ АДРЕСА ДЛЯ ДРУЗЕЙ ================"
if [ -n "$WSS" ]; then
  echo "Интернет (любой город): $WSS"
  printf '%s' "$WSS" | pbcopy
  echo "   ^ адрес уже скопирован в буфер обмена"
fi
echo "Одна Wi-Fi сеть:       ws://$LAN_IP:$PORT"
echo "==================================================="
echo
echo "Друзья: меню «Кооператив» → вставить адрес ретранслятора → «Войти по коду»."
echo "Вы:     «Создать канал» → продиктуйте 4-буквенный код → «Начать вылазку для группы»."
echo "Друг может подключиться даже посреди вылазки — мир синхронизируется сам."
echo "Туннель живёт, пока открыто это окно Terminal."
echo

if [ -n "$WSS" ]; then
  ECHO7_RELAY_URL="$WSS" godot --path game &
else
  ECHO7_RELAY_URL="ws://127.0.0.1:$PORT" godot --path game &
fi
G1=$!
wait $G1
