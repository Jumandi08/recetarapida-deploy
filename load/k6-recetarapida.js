// Pruebas de carga de RecetaRápida API con k6.
// Escenario por variable de entorno: SCENARIO=carga (sostenida), pico, ruptura o humo.
// Uso: k6 run -e SCENARIO=carga -e BASE=http://gateway:8080 load/k6-recetarapida.js
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE || 'http://gateway:8080';
const SCENARIO = __ENV.SCENARIO || 'carga';
// En la ruptura se reduce la espera entre peticiones para aumentar la presión.
const THINK = SCENARIO === 'ruptura' ? 0.1 : 1;
// Escalones de la ruptura: VUs objetivo y duración de cada uno (s).
const PASOS = [200, 400, 600, 800, 1000, 1200, 1400, 1600, 1800, 2000];
const PASO_S = 45;

const escenarios = {
  // Validación del script: 5 VUs durante 15 s.
  humo: { executor: 'constant-vus', vus: 5, duration: '15s' },
  // Carga sostenida: subida a 150 VUs en 2,5 min, meseta de 5 min, bajada de 1,5 min.
  carga: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '2m30s', target: 150 },
      { duration: '5m', target: 150 },
      { duration: '1m30s', target: 0 },
    ],
  },
  // Pico extremo: de 0 a 500 VUs de inmediato, 2 min de pico, caída a 0 y
  // 2 min con 20 VUs para comprobar la recuperación.
  pico: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '1s', target: 500 },
      { duration: '2m', target: 500 },
      { duration: '1s', target: 0 },
      { duration: '30s', target: 0 },
      { duration: '2m', target: 20 },
    ],
  },
  // Ruptura: escalones de +200 VUs cada 45 s (5 s de subida y 40 s de meseta).
  ruptura: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: PASOS.flatMap((v) => [
      { duration: '5s', target: v },
      { duration: `${PASO_S - 5}s`, target: v },
    ]),
  },
};

// Un umbral inofensivo por escalón hace que k6 reporte sus métricas por separado.
const porPaso = {};
if (SCENARIO === 'ruptura') {
  PASOS.forEach((_, i) => {
    porPaso[`http_req_duration{paso:${i + 1}}`] = ['max>=0'];
    porPaso[`http_req_failed{paso:${i + 1}}`] = ['rate>=0'];
  });
}

export const options = {
  scenarios: { [SCENARIO]: escenarios[SCENARIO] },
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: SCENARIO === 'ruptura'
      ? [{ threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '10s' }]
      : ['rate<0.01'],
    ...porPaso,
  },
};

const JSON_H = { 'Content-Type': 'application/json' };

// Un usuario de prueba y un token compartidos por todos los VUs
// (el token dura 24 h, más que cualquier escenario).
export function setup() {
  const stamp = Date.now();
  const mail = `carga.${stamp}@recetarapida.test`;
  const pass = `Carga-${stamp}-pw`;
  const reg = http.post(`${BASE}/api/v1/auth/register`,
    JSON.stringify({ userName: 'Prueba de carga', userMail: mail, userPassword: pass }), { headers: JSON_H });
  if (reg.status !== 201) throw new Error(`registro: ${reg.status}`);
  const login = http.post(`${BASE}/api/v1/auth/login`,
    JSON.stringify({ userMail: mail, userPassword: pass }), { headers: JSON_H });
  const token = login.json('accessToken');
  const vad = http.get(`${BASE}/api/v1/vademecum?size=1`, { headers: { Authorization: `Bearer ${token}` } });
  return { token, vademecumId: vad.json('content.0.id'), mail, t0: Date.now() };
}

export default function (d) {
  const paso = Math.min(PASOS.length, Math.floor((Date.now() - d.t0) / (PASO_S * 1000)) + 1);
  const h = { headers: { Authorization: `Bearer ${d.token}` }, tags: { paso: String(paso) } };
  const r = Math.random();
  let res;
  if (r < 0.35) {
    res = http.get(`${BASE}/api/v1/cie10?q=resfriado&page=1&size=5`, h);
  } else if (r < 0.55) {
    res = http.get(`${BASE}/api/v1/cie10/J00`, h);
  } else if (r < 0.75) {
    res = http.get(`${BASE}/api/v1/vademecum?size=5`, h);
  } else if (r < 0.90) {
    res = http.get(`${BASE}/api/v1/cie10/J00/vademecum`, h);
  } else {
    const receta = {
      paciente: { nombre: 'Paciente de Prueba', edad: 34 },
      profesional: { nombre: 'Dr. Prueba' },
      fecha: new Date().toISOString().slice(0, 10),
      codigosCie10: ['J00'],
      medicamentos: [{ vademecumId: d.vademecumId, dosis: '1 tableta', frecuencia: 'Cada 8 horas', duracion: '5 dias' }],
    };
    res = http.post(`${BASE}/api/v1/recetas`, JSON.stringify(receta), { headers: { ...h.headers, ...JSON_H }, tags: h.tags });
  }
  check(res, { 'status 200': (x) => x.status === 200 });
  sleep(THINK);
}
