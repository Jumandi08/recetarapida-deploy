#!/usr/bin/env bash
# Ejecuta un escenario de k6 dentro de la red interna del stack y guarda
# el resumen, la salida y el consumo de recursos de los contenedores.
# Uso (en el servidor, en la carpeta con k6-recetarapida.js): ./run.sh <carga|pico>
# Durante la prueba limita a 6 CPUs los contenedores de RecetaRápida y al terminar
# vuelve a 16 (todos los núcleos), para no afectar a otros servicios del mismo servidor.
set -u
S=$1
cd "$(dirname "$0")"
CONT="recetarapida-gateway recetarapida-auth recetarapida-prescription recetarapida-postgres"
docker update --cpus 6 $CONT >/dev/null
( while true; do date +%T; docker stats --no-stream --format "{{.Name}} {{.CPUPerc}} {{.MemUsage}}" $CONT; sleep 5; done ) > "recursos-$S.log" 2>&1 &
SAMP=$!
docker run --rm --user "$(id -u)" --name "k6-$S" --network recetarapida_internal --cpus 4 --memory 2g \
  -v "$PWD:/work" -w /work grafana/k6:latest run -e "SCENARIO=$S" -e BASE=http://gateway:8080 \
  --summary-export="resumen-$S.json" k6-recetarapida.js > "salida-$S.txt" 2>&1
kill $SAMP
docker update --cpus 16 $CONT >/dev/null
echo FIN > "fin-$S.txt"
