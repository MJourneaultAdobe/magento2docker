#!/usr/bin/env bash
# shellcheck shell=bash

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

[[ -n "${_LIB_SYNC_SH:-}" ]] && return "${RC_OK}"
source "${M2D_LIBRARIES_ROOT}/env.sh" || return "${RC_ERROR}"
readonly _LIB_SYNC_SH=1

sync::run() {
    local action="$1"
    local envFile="$2"
    local projectPath="$3"
    local syncType syncDir serverVendor
    syncType=$(env::getParameter "$envFile" M2D_SOURCE_DIRECTORY_SYNC_TYPE) || return "${RC_ERROR}"
    syncDir=$(env::getParameter "$envFile" M2D_SOURCE_DIRECTORY) || return "${RC_ERROR}"
    serverVendor=$(env::getParameter "$envFile" M2D_WEB_SERVER_VENDOR) || return "${RC_ERROR}"

    case $syncType in
        'bind')
            echo "For '$syncType' sync type there are no sync actions to execute."
            ;;
        'sshfs')
            local sshPort
            sshPort=$(env::getParameter "$envFile" M2D_PORT_FOR_WEB_SERVER_SSH) || return "${RC_ERROR}"
            case $action in
                'start')
                    local identityFile="$projectPath/services/web-servers/$serverVendor/etc/ssh/magento2docker"
                    chmod 400 "$identityFile" || return "${RC_ERROR}"
                    sshfs magento@127.0.0.1:/var/www/html "$syncDir" \
                        -o reconnect \
                        -o StrictHostKeyChecking=no \
                        -o follow_symlinks \
                        -o IdentityFile="$identityFile" \
                        -o port="$sshPort" \
                        -o compression=no || return "${RC_ERROR}"
                    ;;
                'stop'|'pause')
                    umount -f "$syncDir" || return "${RC_ERROR}"
                    ;;
                'restart')
                    sync::run stop "$envFile" "$projectPath" || return "${RC_ERROR}"
                    sync::run start "$envFile" "$projectPath" || return "${RC_ERROR}"
                    ;;
                *)
                    message::error "For '$syncType' sync type allowed actions are: start, stop, pause, and restart"
                    return "${RC_ERROR}"
                    ;;
            esac
            ;;
        'mutagen')
            local suffix syncName syncWeb
            suffix=$(env::getParameter "$envFile" M2D_PROJECT_SUFFIX) || return "${RC_ERROR}"
            syncName="m2d-sync$suffix"
            syncWeb="m2d-web$suffix"
            case $action in
                'start')
                    local sessions
                    sessions=$(mutagen sync list) || return "${RC_ERROR}"
                    if [[ -n $(grep "^Name: $syncName$" <<< "$sessions") ]]; then
                        mutagen sync resume "$syncName" || return "${RC_ERROR}"
                    else
                        mutagen sync create --name="$syncName" \
                            --default-group-beta=magento \
                            --default-owner-beta=magento \
                            --sync-mode=two-way-resolved \
                            --default-file-mode=0664 \
                            --default-directory-mode=0755 \
                            --ignore=/.idea \
                            --ignore=/.magento \
                            --ignore=/.docker \
                            --ignore=/.github \
                            --ignore-vcs \
                            --ignore=/**/var/cache \
                            --ignore=/**/var/page_cache \
                            --ignore=/**/var/session \
                            --ignore=/**/var/log \
                            --ignore=/**/.DS_Store \
                            --symlink-mode=posix-raw \
                            --probe-mode=assume \
                            --scan-mode=accelerated \
                            --stage-mode=internal \
                            --watch-mode=portable \
                            --watch-polling-interval=20 \
                            "$syncDir" \
                            "docker://magento@$syncWeb/var/www/html/" || return "${RC_ERROR}"
                    fi
                    ;;
                'pause')
                    mutagen sync pause "$syncName" || return "${RC_ERROR}"
                    ;;
                'stop')
                    mutagen sync terminate "$syncName" || return "${RC_ERROR}"
                    ;;
                'status')
                    mutagen sync monitor "$syncName" || return "${RC_ERROR}"
                    ;;
                'restart')
                    sync::run stop "$envFile" "$projectPath" || return "${RC_ERROR}"
                    sync::run start "$envFile" "$projectPath" || return "${RC_ERROR}"
                    ;;
                'fix')
                    mutagen sync reset "$syncName" && mutagen sync flush "$syncName" || return "${RC_ERROR}"
                    ;;
                *)
                    message::error "For '$syncType' sync type allowed actions are: start, stop, pause, restart, status and fix"
                    return "${RC_ERROR}"
                    ;;
            esac
            ;;
        *)
            message::error "Sync type '$syncType' is not supported!"
            return "${RC_ERROR}"
            ;;
    esac
}
