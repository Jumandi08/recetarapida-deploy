#!/bin/sh
# Se ejecuta una sola vez, al crear el volumen de datos de PostgreSQL.
# Crea una base y un rol propietario por microservicio: cada servicio solo
# puede entrar en su base, y ninguno usa el superusuario.
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<SQL
CREATE ROLE usuarios_app LOGIN PASSWORD '${AUTH_DB_PASSWORD}';
CREATE ROLE prescriptions_app LOGIN PASSWORD '${PRESCRIPTIONS_DB_PASSWORD}';

CREATE DATABASE usuarios_db OWNER usuarios_app;
CREATE DATABASE prescriptions_db OWNER prescriptions_app;

REVOKE ALL ON DATABASE usuarios_db FROM PUBLIC;
REVOKE ALL ON DATABASE prescriptions_db FROM PUBLIC;
SQL
