#!/bin/sh
set -eu
: "${ANSIBLE_VAULT_PASSWORD:?ANSIBLE_VAULT_PASSWORD is not set}"
printf '%s' "$ANSIBLE_VAULT_PASSWORD"
