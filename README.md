# RecetaRápida · Despliegue

Despliegue de producción de RecetaRápida (API + web) en contenedores. Reúne en un
solo `docker-compose.yml` el front web, el gateway, el servicio de autenticación,
el servicio de prescripciones y PostgreSQL, y los publica en
`https://recetarapida.ansayan.com`.

## Arquitectura de despliegue

```text
Internet ──► Cloudflare (TLS) ──► túnel ──► Traefik ──► front :80 (nginx)
                                                          │  sirve la SPA y proxya /api/
                                                          ▼
                                                     gateway :8080
                                                          │  red interna recetarapida_internal
                                          ┌───────────────┴────────────────┐
                                          ▼                                ▼
                                msa-authentication :8082     msa-quick-prescription :8081
                                          │                                │
                                          └──────────► postgres :5432 ◄────┘
                                                  usuarios_db · prescriptions_db
```

- Solo el **front** está conectado a la red `coolify` de Traefik. nginx sirve la
  SPA y hace de reverse-proxy de `/api/` hacia el gateway, de modo que la web y
  la API comparten origen (sin CORS). El gateway y los demás contenedores no
  publican puertos.
- PostgreSQL 16 aloja dos bases, `usuarios_db` y `prescriptions_db`. Cada una
  tiene su propio rol propietario (`usuarios_app`, `prescriptions_app`); ningún
  servicio usa el superusuario. El script que las crea es
  `docker/postgres/10-init-databases.sh`.
- Los esquemas los crea Flyway al arrancar cada servicio.
- Los datos viven en el volumen `recetarapida_pgdata`.

## Qué cambia respecto al compose de desarrollo

| Desarrollo (`gtw-quick-prescription`) | Producción (este repo) |
|---|---|
| `build.context: ../msa-...` (carpetas hermanas) | Contexto por URL de Git, con `REF_*` para fijar rama o commit |
| Puertos 5432, 8080, 8081 y 8082 en el host | Ninguno publicado; la app entra por Traefik vía el front |
| Contraseñas y secreto JWT con valores por defecto | `.env` obligatorio, sin valores por defecto y con secretos aleatorios |
| Un solo usuario `postgres` para todo | Un rol por base de datos |
| Sin reinicio automático ni límites | `restart: unless-stopped` y `mem_limit` por servicio |

## Requisitos del servidor

Docker Engine con Compose v2 y la red externa `coolify` (la crea Coolify).
El dominio debe llegar a Traefik; en este homelab lo cubre el comodín
`*.ansayan.com` del túnel de Cloudflare.

## Desplegar

Desde el Mac, con acceso `ssh homelab`:

```bash
scripts/deploy.sh
```

El script copia los archivos a `~/stacks/recetarapida`, crea `.env` con secretos
aleatorios si no existe (permisos 600) y ejecuta `docker compose up -d --build`.
Se puede repetir sin perder datos. Para desplegar un commit concreto, edita
`REF_AUTH`, `REF_PRESCRIPTION`, `REF_GATEWAY` o `REF_FRONT` en el `.env` del servidor.

## Verificar

```bash
scripts/smoke-test.sh                       # contra https://recetarapida.ansayan.com
scripts/smoke-test.sh http://localhost:8080 # contra otra URL
```

Registra un usuario de prueba, inicia sesión, consulta CIE-10 y vademécum,
genera una receta en PDF y comprueba que sin token la API responde 401.
Cada ejecución deja un usuario `smoke.<marca>@recetarapida.test`; para
limpiarlos:

```bash
docker compose exec -T postgres psql -U postgres -d usuarios_db \
  -c "delete from users where user_mail like '%@recetarapida.test'"
```

## Pipeline de CI

`.github/workflows/ci.yml` corre en cada push a `main`, en cada pull request y a
mano. Revisa los scripts con ShellCheck, valida el compose, construye las cuatro
imágenes desde los repositorios del equipo, levanta el stack completo con su
propia instancia de PostgreSQL, espera a que la app responda a través del front y
ejecuta `scripts/smoke-test.sh` contra él. Si algo falla, muestra los registros
de los contenedores; al final siempre apaga el stack. `ci/docker-compose.ci.yml`
solo añade la publicación del puerto 80 del front (en el 8080 del runner).

El despliegue al servidor sigue siendo manual (`scripts/deploy.sh`) y se lanza
cuando el pipeline pasa.

## Operación

```bash
ssh homelab
cd ~/stacks/recetarapida
docker compose ps
docker compose logs -f front                          # nginx del front (acceso público)
docker compose logs -f gateway                        # gateway interno
docker compose up -d --build msa-quick-prescription   # reconstruir un servicio
docker compose up -d --build front                    # reconstruir solo el front
docker compose exec postgres psql -U postgres -c '\l' # listar bases
```

Para consultar la base desde el Mac sin exponerla, abre un túnel al puerto de
loopback del servidor: `ssh -L 5435:127.0.0.1:5435 homelab`.

Respaldo de las dos bases:

```bash
docker compose exec -T postgres pg_dump -U postgres usuarios_db > usuarios_db.sql
docker compose exec -T postgres pg_dump -U postgres prescriptions_db > prescriptions_db.sql
```

## Seguridad

- `.env` no se versiona. Sin sus variables obligatorias, Compose se niega a arrancar.
- El servicio de autenticación incluye cuatro usuarios de ejemplo en su
  migración `V2__seed_default_users.sql`, entre ellos un administrador. Cambia o
  elimina esas cuentas antes de usar la API con datos reales.
- Las pruebas de carga contra la URL pública pasan por Cloudflare, que puede
  limitar el tráfico. Para medir la API y no el proxy, ejecútalas desde dentro
  de la red del servidor.
