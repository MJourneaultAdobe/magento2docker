#!/usr/bin/env bash
# shellcheck shell=bash

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

[[ -n "${_LIB_CONTAINER_SH:-}" ]] && return "${RC_OK}"
source "${M2D_LIBRARIES_ROOT}/sync.sh" || return "${RC_ERROR}"
readonly _LIB_CONTAINER_SH=1

container::_compose() {
    local projectPath="$1"
    local syncType
    shift

    syncType=$(env::getParameter "$projectPath/.env" M2D_SOURCE_DIRECTORY_SYNC_TYPE) || return "${RC_ERROR}"
    if [[ $syncType == 'bind' ]]; then
        docker-compose --project-directory "$projectPath" \
            -f "$projectPath/docker-compose.yml" \
            -f "$projectPath/docker-compose.bind.yml" \
            "$@" || return "${RC_ERROR}"
    else
        docker-compose --project-directory "$projectPath" "$@" || return "${RC_ERROR}"
    fi
}

container::build() {
    container::_compose "$1" build
}

container::down() {
    local projectPath="$1"

    docker-compose --project-directory "$projectPath" down || return "${RC_ERROR}"
    sync::run stop "$projectPath/.env" "$projectPath"
}

container::exec() {
    local containerName="$1"
    local userName="${2:-root}"
    local allowed
    allowed=$(docker ps --format '{{.Names}}' | grep "$containerName")

    if [[ -n "$allowed" ]]; then
        docker exec -it --user "$userName" "$containerName" /bin/bash || return "${RC_ERROR}"
    else
        message::error "Sorry, container '$containerName' doesn't exist!"
        return "${RC_ERROR}"
    fi
}

container::execWeb() {
    local projectPath="$1"
    local suffix
    suffix=$(env::getParameter "$projectPath/.env" M2D_PROJECT_SUFFIX) || return "${RC_ERROR}"

    docker exec -it --env COLUMNS="$(tput cols)" --env LINES="$(tput lines)" \
        --user magento "m2d-web$suffix" bash || return "${RC_ERROR}"
}

container::logs() {
    local containerName="$1"
    local allowed
    allowed=$(docker ps --format '{{.Names}}' | grep "$containerName")

    if [[ -n "$allowed" ]]; then
        docker logs -f "$containerName" || return "${RC_ERROR}"
    else
        message::error "Sorry, container '$containerName' doesn't exist!"
        return "${RC_ERROR}"
    fi
}

container::stop() {
    local projectPath="$1"

    docker-compose --project-directory "$projectPath" stop || return "${RC_ERROR}"
    sync::run pause "$projectPath/.env" "$projectPath"
}

container::up() {
    local projectPath="$1"
    local build="${2:-}"

    if [[ $build == '-b' || $build == '--build' ]]; then
        container::_compose "$projectPath" up -d --build || return "${RC_ERROR}"
    else
        docker-compose --project-directory "$projectPath" up -d || return "${RC_ERROR}"
    fi
    sync::run start "$projectPath/.env" "$projectPath"
}
