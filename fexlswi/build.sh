#!/bin/sh
# Compatibilidad: el perfil por defecto es selfh (todo estatico).
# Para elegir: make opt / make selfh / make clean.
cd "$(dirname "$0")"
exec make selfh "$@"
