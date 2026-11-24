#!/usr/bin/env bash
# shellcheck shell=bash

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

[[ -n "${_LIB_HELP_SH:-}" ]] && return "${RC_OK}"
readonly _LIB_HELP_SH=1

help::enableDisable() {
    local command="$1"
    local Command="${1^}"

    echo "
Usage: ./m2d $command [OPTIONS] COMMAND

$Command selected service or tool.

Example:
./m2d $command mailcatcher

Options:
  -h, --help Display help for command

Commands:
  blackfire       $Command blackfire container
  db-cache        $Command db-cache container
  elastic         Alias for 'search-engine ' command
  m               Alias for 'mailcatcher' command
  mailcatcher     $Command mailcatcher container
  message-broker  $Command message broker container
  rabbit          Alias for 'message-broker' command
  redis           Alias for 'db-cache' command
  search-engine   $Command search engine container
  selenium        $Command selenium container
  varnish         Alias for 'web-cache' command
  web-cache       $Command web-cache container

After container is $command it must be rebuild with: \`./m2d build\` or \`./m2d up --build\`
"
}

help::genericCommand() {
    echo "
Usage: ./m2d $1 [OPTIONS]

Options:
  -h, --help   Display help for command
"
}

help::go() {
    echo "
Usage: ./m2d go [OPTIONS] CONTAINER_NAME

Enters a running container.

Example:
./m2d go web

Options:
  -h, --help Display help for command

Containers:
  web       Alias for m2d-web container

Current containers:
"
    docker ps --format '{{.Names}}'
}

help::logs() {
    echo "
Usage: ./m2d logs [OPTIONS] CONTAINER_NAME

View logs from containers.

Options:
  -h, --help Display help for command

Current containers:
"
    docker ps --format '{{.Names}}'
}

help::main() {
    echo "
Usage: ./m2d COMMAND [OPTIONS]

Examples:
- initial setup:
./m2d setup init

- build and start containers:
./m2d up --build

- stop and remove containers and networks:
./m2d down


Options:
  -h, --help Display help for command

Commands:
  build    Build or rebuild containers
  disable  Disable selected service or tool
  down     Stop and remove containers and networks
  enable   Enable selected service or tool
  go       Enters a running container
  logs     View logs from containers
  set      Sets configuration value
  setup    Configure project
  show     Shows configuration value
  stop     Stops containers
  sync     Manage data sync from between host and containers
  up       Create and start containers
"
}

help::set() {
    echo "
Usage: ./m2d set [OPTIONS] PARAMETER VALUE

Sets configuration value.

Examples:
./m2d set M2D_XDEBUG_IDE_KEY VSCODE
./m2d set es 8.4

Options:
  -h, --help Display help for command

Parameters:
  es       Alias for setting Elasticsearch as the search engine. It will set M2D_SEARCH_ENGINE_VENDOR to 'elasticsearch',
           and M2D_SEARCH_ENGINE_VERSION to '7' if the expected version is not provided as a value
  php      Alias for parameter M2D_WEB_SERVER_PHP_VERSION
  suffix   Alias for parameter M2D_PROJECT_SUFFIX
  [M2D_*]  Parameter name. A list of possible parameters and their values is in the '.env.example' file
"
}

help::setup() {
    echo "
Usage: ./m2d setup [OPTIONS] [COMMAND] [PROJECT_ID]

Configure project.

Example:
./m2d setup init

Options:
  -h, --help Display help for command

Commands:
  init        Starts creator of initial configuration for Web container and .env file
  env         Starts .env file creator
  from-cloud  Generates .env file based on provided PROJECT_ID
"
}

help::show() {
    echo "
Usage: ./m2d show [OPTIONS] PARAMETER

Shows configuration value.

Example:
./m2d show M2D_SOURCE_DIRECTORY

Options:
  -h, --help Display help for command

Parameters:
  home     Display path to the directory where Magento2Docker is installed
  src      Display path to the source directory [M2D_SOURCE_DIRECTORY]
  [M2D_*]  Parameter name. A list of possible parameters is in the '.env.example' file
"
}

help::sync() {
    echo "
Usage: ./m2d sync [OPTIONS] ACTION

Manage data sync from between host and containers.

Options:
  -h, --help Display help for command

Actions:
  start    Starts synchronization if applicable
  pause    Pause synchronization if applicable
  stop     Stops synchronization if applicable
  status   Display synchronization status if applicable
  restart  Restart synchronization if applicable
"
}

help::up() {
    echo "
Usage: ./m2d up [OPTIONS]

Create and start containers.

Options:
  -h, --help   Display help for command
  -b, --build  Build images before starting containers.
"
}
