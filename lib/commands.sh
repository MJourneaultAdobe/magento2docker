#!/usr/bin/env bash
# shellcheck shell=bash

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

[[ -n "${_LIB_COMMANDS_SH:-}" ]] && return "${RC_OK}"
source "${M2D_LIBRARIES_ROOT}/container.sh" || return "${RC_ERROR}"
source "${M2D_LIBRARIES_ROOT}/env.sh" || return "${RC_ERROR}"
source "${M2D_LIBRARIES_ROOT}/help.sh" || return "${RC_ERROR}"
source "${M2D_LIBRARIES_ROOT}/setup.sh" || return "${RC_ERROR}"
source "${M2D_LIBRARIES_ROOT}/sync.sh" || return "${RC_ERROR}"
readonly _LIB_COMMANDS_SH=1

commands::run() {
    local projectPath="$1"
    local envFile="$projectPath/.env"
    shift

    case ${1:-} in
        'set')
            case ${2:-} in
                '-h'|'--help')
                    help::set
                    ;;
                'suffix')
                    env::setParameter "$envFile" M2D_PROJECT_SUFFIX "${3:-}"
                    ;;
                'php')
                    env::setParameter "$envFile" M2D_WEB_SERVER_PHP_VERSION "${3:-}"
                    ;;
                'es')
                    env::setParameter "$envFile" M2D_SEARCH_ENGINE_VENDOR elasticsearch || return "${RC_ERROR}"
                    env::setParameter "$envFile" M2D_SEARCH_ENGINE_VERSION "${3:-7}"
                    ;;
                *)
                    env::setParameter "$envFile" "${2:-}" "${3:-}"
                    ;;
            esac
            ;;
        'show')
            case ${2:-} in
                '-h'|'--help')
                    help::show
                    ;;
                'home')
                    echo "$projectPath"
                    ;;
                'src')
                    env::getParameter "$envFile" M2D_SOURCE_DIRECTORY
                    ;;
                *)
                    env::getParameter "$envFile" "${2:-}"
                    ;;
            esac
            ;;
        'setup')
            case ${2:-} in
                'init')
                    setup::init "$projectPath"
                    ;;
                'env')
                    setup::initEnv "$envFile"
                    ;;
                'from-cloud')
                    echo 'Not yet implemented!'
                    ;;
                *)
                    help::setup
                    ;;
            esac
            ;;
        'enable'|'disable')
            local command="$1"
            local enabled=no
            [[ $command == 'enable' ]] && enabled=yes

            case ${2:-} in
                '-h'|'--help')
                    help::enableDisable "$command"
                    ;;
                'blackfire')
                    env::setParameter "$envFile" M2D_ENABLE_BLACKFIRE "$enabled"
                    ;;
                'mailcatcher'|'m')
                    env::setParameter "$envFile" M2D_ENABLE_MAILCATCHER "$enabled"
                    ;;
                'selenium')
                    env::setParameter "$envFile" M2D_ENABLE_SELENIUM "$enabled"
                    ;;
                'web-cache'|'varnish')
                    env::setParameter "$envFile" M2D_ENABLE_WEB_CACHE "$enabled"
                    ;;
                'db-cache'|'redis')
                    env::setParameter "$envFile" M2D_ENABLE_DB_CACHE "$enabled"
                    ;;
                'message-broker'|'rabbit')
                    env::setParameter "$envFile" M2D_ENABLE_MESSAGE_BROKER "$enabled"
                    ;;
                'search-engine'|'elastic')
                    env::setParameter "$envFile" M2D_ENABLE_SEARCH_ENGINE "$enabled"
                    ;;
            esac
            ;;
        'up')
            case ${2:-} in
                '-h'|'--help')
                    help::up
                    ;;
                *)
                    container::up "$projectPath" "${2:-}"
                    ;;
            esac
            ;;
        'down')
            case ${2:-} in
                '-h'|'--help')
                    help::genericCommand down
                    ;;
                *)
                    container::down "$projectPath"
                    ;;
            esac
            ;;
        'stop')
            case ${2:-} in
                '-h'|'--help')
                    help::genericCommand stop
                    ;;
                *)
                    container::stop "$projectPath"
                    ;;
            esac
            ;;
        'build')
            case ${2:-} in
                '-h'|'--help')
                    help::genericCommand build
                    ;;
                *)
                    container::build "$projectPath"
                    ;;
            esac
            ;;
        'go')
            case ${2:-} in
                '-h'|'--help')
                    help::go
                    ;;
                'web')
                    container::execWeb "$projectPath"
                    ;;
                *)
                    container::exec "${2:-}" "${3:-root}"
                    ;;
            esac
            ;;
        'logs')
            case ${2:-} in
                '-h'|'--help')
                    help::logs
                    ;;
                *)
                    container::logs "${2:-}"
                    ;;
            esac
            ;;
        'sync')
            case ${2:-} in
                '-h'|'--help')
                    help::sync
                    ;;
                *)
                    sync::run "${2:-}" "$envFile" "$projectPath"
                    ;;
            esac
            ;;
        *)
            help::main
            ;;
    esac
}
