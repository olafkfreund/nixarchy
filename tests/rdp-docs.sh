#!/usr/bin/env bash
set -euo pipefail

secrets=$1
flake=$2
manual=$3
options=$4

need() {
  if ! grep -Fq -- "$2" "$1"; then
    printf 'rdp-docs: %s lacks %s\n' "$1" "$2" >&2
    exit 1
  fi
}

reject() {
  if grep -Fq -- "$2" "$1"; then
    printf 'rdp-docs: %s still says %s\n' "$1" "$2" >&2
    exit 1
  fi
}

need "$secrets" 'v0.1.6 supports `password_file`'
need "$secrets" 'service start'
need "$secrets" '`HalfCredentials`'
reject "$secrets" 'There is no `password_file` option'

need "$flake" 'v0.1.6'
need "$flake" '`password_file`'
need "$flake" 'service start'
reject "$flake" 'there is no `password_file`'
reject "$flake" 'It reads its password from exactly two'

need "$manual" 'v0.1.6'
need "$manual" 'named `password_file`'
need "$manual" '`HalfCredentials`'
need "$manual" 'service start'
reject "$manual" 'reads it from exactly two places'
reject "$manual" 'the config file at activation'

need "$options" 'v0.1.6, src/config.rs:301-361'
need "$options" '`HalfCredentials`'
need "$options" 'src/server/mod.rs:200-206'
reject "$options" 'hypr-rdp reads its password only from an inline string'

printf 'rdp-docs: current hypr-rdp documentation verified\n'
