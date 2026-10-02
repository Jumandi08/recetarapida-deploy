#!/usr/bin/env bash
# Prueba de humo contra la API desplegada: registro, login, catálogos, receta
# en PDF y rechazo sin token. Crea un usuario de prueba con correo único.
#
# Uso: scripts/smoke-test.sh [URL-base]   (por defecto: https://recetarapida.ansayan.com)
set -euo pipefail

BASE="${1:-https://recetarapida.ansayan.com}"
STAMP="$(date +%s)"
MAIL="smoke.${STAMP}@recetarapida.test"
PASS="Smoke-${STAMP}-pw"
OUT="$(mktemp -d)"
fail=0

check() { # nombre esperado obtenido
  if [ "$2" = "$3" ]; then printf '  OK   %-46s %s\n' "$1" "$3"
  else printf '  FALLA %-45s esperado %s, obtuvo %s\n' "$1" "$2" "$3"; fail=1; fi
}
code() { curl -s -o "$OUT/body" -w '%{http_code}' "$@"; }

REGISTRO="{\"userName\":\"Prueba de humo\",\"userMail\":\"$MAIL\",\"userPassword\":\"$PASS\"}"
LOGIN_OK="{\"userMail\":\"$MAIL\",\"userPassword\":\"$PASS\"}"
LOGIN_MAL="{\"userMail\":\"$MAIL\",\"userPassword\":\"incorrecta-123\"}"
JSON='Content-Type: application/json'

echo "Probando ${BASE}"
check "GET /cie10 sin token -> 401" 401 "$(code "$BASE/api/v1/cie10")"
check "POST /auth/register -> 201" 201 "$(code -X POST "$BASE/api/v1/auth/register" -H "$JSON" -d "$REGISTRO")"
check "POST /auth/login -> 200" 200 "$(code -X POST "$BASE/api/v1/auth/login" -H "$JSON" -d "$LOGIN_OK")"
TOKEN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["accessToken"])' "$OUT/body")"
AUTH=(-H "Authorization: Bearer $TOKEN")

check "POST /auth/login clave mala -> 401" 401 "$(code -X POST "$BASE/api/v1/auth/login" -H "$JSON" -d "$LOGIN_MAL")"
check "GET /cie10?q=resfriado -> 200" 200 "$(code "${AUTH[@]}" "$BASE/api/v1/cie10?q=resfriado&page=1&size=5")"
check "GET /cie10/J00 -> 200" 200 "$(code "${AUTH[@]}" "$BASE/api/v1/cie10/J00")"
check "GET /vademecum -> 200" 200 "$(code "${AUTH[@]}" "$BASE/api/v1/vademecum?size=1")"
VID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["content"][0]["id"])' "$OUT/body")"
check "GET /cie10/J00/vademecum -> 200" 200 "$(code "${AUTH[@]}" "$BASE/api/v1/cie10/J00/vademecum")"
check "GET /cie10/ZZZ -> 400" 400 "$(code "${AUTH[@]}" "$BASE/api/v1/cie10/ZZZ")"

RECETA="{\"paciente\":{\"nombre\":\"Paciente de Prueba\",\"edad\":34},\"profesional\":{\"nombre\":\"Dr. Prueba\"},\"fecha\":\"$(date +%F)\",\"codigosCie10\":[\"J00\"],\"medicamentos\":[{\"vademecumId\":$VID,\"dosis\":\"1 tableta\",\"frecuencia\":\"Cada 8 horas\",\"duracion\":\"5 dias\"}]}"
check "POST /recetas -> 200" 200 "$(curl -s -o "$OUT/receta.pdf" -w '%{http_code}' -X POST "$BASE/api/v1/recetas" \
  "${AUTH[@]}" -H "$JSON" -d "$RECETA")"
check "Receta es un PDF" "%PDF" "$(head -c 4 "$OUT/receta.pdf")"

rm -rf "$OUT"
[ "$fail" -eq 0 ] && echo "Todo en orden." || { echo "Hay pruebas fallidas."; exit 1; }
