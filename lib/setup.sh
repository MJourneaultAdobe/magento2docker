#!/usr/bin/env bash
# shellcheck shell=bash

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

[[ -n "${_LIB_SETUP_SH:-}" ]] && return "${RC_OK}"
source "${M2D_LIBRARIES_ROOT}/env.sh" || return "${RC_ERROR}"
readonly _LIB_SETUP_SH=1

setup::_initSourceFolder() {
    local envFile="$1"
    local currentFolder newFolder
    currentFolder=$(env::getParameter "$envFile" M2D_SOURCE_DIRECTORY) || return "${RC_ERROR}"

    local prompt="Magento2Docker, depending on the sync type, will sync or bind '/var/www/html' path in a container to a local folder on the host.
Please provide a complete or relative path to the folder you want to use for this, e.g., '/Users/adam/src' or '~/src'
Type the path to a folder you want to use or leave it empty to keep the current '$currentFolder': "

    read -r -p "$prompt" newFolder

    if [[ -z "$newFolder" ]]; then
        newFolder="$currentFolder"
    fi

    newFolder="${newFolder/#\~/$HOME}"

    if [[ ! -d "$newFolder" ]]; then
        local confirm
        read -r -p "Path '$newFolder' doesn't exist. Do you want to create it? [y/n]: " confirm
        if [[ $confirm == 'y' ]]; then
            mkdir -p "$newFolder" || return "${RC_ERROR}"
        fi
    fi

    echo "$newFolder"
}

setup::init() {
    local projectPath="$1"

    setup::initEnv "$projectPath/.env" || return "${RC_ERROR}"
    source "$projectPath/services/web-servers/apache/bin/install.sh" || return "${RC_ERROR}"
}

setup::initEnv() {
    local envFile="$1"
    local value="" confirm

    echo 'Initializing project...'
    if [[ -f "$envFile" ]]; then
        read -r -p 'You already have .env settings file. You can keep it (n) or recreate it (y). Do you want to recreate it? [y/n]: ' confirm
        if [[ $confirm == 'y' ]]; then
            cp "$envFile.example" "$envFile" || return "${RC_ERROR}"
        fi
    else
        cp "$envFile.example" "$envFile" || return "${RC_ERROR}"
    fi

    read -r -p 'Do you want to provide core Magento2Docker settings (y) or do you want to use current (n)? [y/n]: ' confirm
    if [[ $confirm != 'y' ]]; then
        echo "Magento2Docker will use settings from this file: '$envFile'"
        echo 'Please verify them before further usage!'
        return "${RC_OK}"
    fi

    while [[ ! -d "$value" ]]; do
        value=$(setup::_initSourceFolder "$envFile") || return "${RC_ERROR}"
    done
    env::setParameter "$envFile" M2D_SOURCE_DIRECTORY "$value" || return "${RC_ERROR}"

    read -r -p 'Are you on Apple M1/M2 chip? [y/n]: ' confirm
    if [[ $confirm == 'y' ]]; then
        env::setParameter "$envFile" M2D_CPU_TYPE m1 || return "${RC_ERROR}"
    else
        env::setParameter "$envFile" M2D_CPU_TYPE intel || return "${RC_ERROR}"
    fi

    value=$(env::getParameter "$envFile" M2D_XDEBUG_IDE_KEY) || return "${RC_ERROR}"
    read -r -p "Provide IDE key to be used by xDebug (e.g.: PHPSTORM, VSCODE) or leave it empty to keep the current '$value': " value
    if [[ -n $value ]]; then
        env::setParameter "$envFile" M2D_XDEBUG_IDE_KEY "$value" || return "${RC_ERROR}"
    fi

    value=$(env::getParameter "$envFile" MAGENTO_CLOUD_CLI_TOKEN) || return "${RC_ERROR}"
    read -r -p "Provide Magento Cloud CLI authentication token or leave it empty to keep the current '$value': " value
    if [[ -n $value ]]; then
        env::setParameter "$envFile" MAGENTO_CLOUD_CLI_TOKEN "$value" || return "${RC_ERROR}"
    fi
}
