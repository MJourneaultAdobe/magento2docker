#!/usr/bin/env bash
# shellcheck shell=bash

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

[[ -n "${_LIB_ENV_SH:-}" ]] && return "${RC_OK}"
source "${M2D_LIBRARIES_ROOT}/message.sh" || return "${RC_ERROR}"
readonly _LIB_ENV_SH=1

env::getParameter() {
    local envFile="$1"
    local parameter="$2"
    local default="${3:-}"
    local value

    if [[ ! -f "$envFile" ]]; then
        message::error "Env file '$envFile' doesn't exist! Initialize it by executing \`./m2d setup env\`"
        return "${RC_ERROR}"
    fi

    value=$(grep "^$parameter=" "$envFile" | cut -d '=' -f 2 | tr -d "'")
    value="${value:=$default}"

    echo "$value"
}

env::setParameter() {
    local envFile="$1"
    local parameter="$2"
    local value="$3"

    if [[ ! -f "$envFile" ]]; then
        message::error "Env file '$envFile' doesn't exist! Initialize it by executing \`./m2d setup env\`"
        return "${RC_ERROR}"
    fi

    if grep -q "^${parameter}=" "$envFile"; then
        sed -i.back "s|^\\(${parameter}=\\).*|\\1'$value'|" "$envFile" || return "${RC_ERROR}"
    else
        [[ ! -s "$envFile" || -z "$(tail -c 1 "$envFile")" ]] || echo >> "$envFile" || return "${RC_ERROR}"
        printf "%s='%s'\n" "$parameter" "$value" >> "$envFile" || return "${RC_ERROR}"
    fi
}
