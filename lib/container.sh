#!/usr/bin/env bash
# shellcheck shell=bash

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

[[ -n "${_LIB_CONTAINER_SH:-}" ]] && return "${RC_OK}"
source "${M2D_LIBRARIES_ROOT}/sync.sh" || return "${RC_ERROR}"
readonly _LIB_CONTAINER_SH=1

container::_compose() {
    local projectPath="$1"
    local profileScope="$2"
    local syncType service
    local -a files=() profiles=()
    shift 2

    syncType=$(env::getParameter "$projectPath/.env" M2D_SOURCE_DIRECTORY_SYNC_TYPE) || return "${RC_ERROR}"
    if [[ $syncType == 'bind' ]]; then
        files=(-f "$projectPath/docker-compose.yml" -f "$projectPath/docker-compose.bind.yml")
    fi
    for service in $(container::_optionalServices "$projectPath" "$profileScope"); do
        profiles+=(--profile "$service")
    done

    docker-compose --project-directory "$projectPath" "${files[@]}" "${profiles[@]}" "$@" || return "${RC_ERROR}"
}

# Outputs the optional services (compose profiles) of a scope: enabled, disabled or all.
container::_optionalServices() {
    local projectPath="$1"
    local scope="$2"
    local group service enabled
    local -A defaults=([DB_ENGINE]=yes [SEARCH_ENGINE]=yes)
    local -A services=(
        [DB_ENGINE]=db [SEARCH_ENGINE]=search_engine [DB_CACHE]=db_cache
        [MESSAGE_BROKER]=message_broker [WEB_CACHE]=web_cache
        [MAILCATCHER]=mailcatcher [BLACKFIRE]=blackfire [SELENIUM]=selenium
    )

    for group in DB_ENGINE SEARCH_ENGINE DB_CACHE MESSAGE_BROKER WEB_CACHE MAILCATCHER BLACKFIRE SELENIUM; do
        service="${services[$group]}"
        if [[ $scope != 'all' ]]; then
            enabled=$(env::getParameter "$projectPath/.env" "M2D_ENABLE_${group}" "${defaults[$group]:-no}") || return "${RC_ERROR}"
            [[ $scope == 'enabled' && $enabled != 'yes' ]] && continue
            [[ $scope == 'disabled' && $enabled == 'yes' ]] && continue
        fi
        echo "$service"
    done
}

container::_removeDisabled() {
    local projectPath="$1"
    local -a disabled=()

    mapfile -t disabled < <(container::_optionalServices "$projectPath" disabled)
    (( ${#disabled[@]} > 0 )) || return "${RC_OK}"
    container::_compose "$projectPath" disabled rm --stop --force "${disabled[@]}" || return "${RC_ERROR}"
}

container::build() {
    container::_compose "$1" enabled build
}

container::down() {
    local projectPath="$1"

    container::_compose "$projectPath" all down || return "${RC_ERROR}"
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

    container::_compose "$projectPath" all stop || return "${RC_ERROR}"
    sync::run pause "$projectPath/.env" "$projectPath"
}

container::up() {
    local projectPath="$1"
    local build="${2:-}"

    if [[ $build == '-b' || $build == '--build' ]]; then
        container::_compose "$projectPath" enabled up -d --build || return "${RC_ERROR}"
    else
        container::_compose "$projectPath" enabled up -d || return "${RC_ERROR}"
    fi
    container::_removeDisabled "$projectPath" || return "${RC_ERROR}"
    sync::run start "$projectPath/.env" "$projectPath"
}
