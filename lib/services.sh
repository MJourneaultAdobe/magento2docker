#!/usr/bin/env bash
###########################################################
# Commerce stack configuration: resolves the service
# versions supported by a Commerce version from the system
# requirements matrix, saves them to the .env file and
# starts the selected services.
###########################################################

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

# Prevent the library from being sourced more than once.
[[ -n "${_LIB_SERVICES_SH:-}" ]] && return
readonly _LIB_SERVICES_SH=1

source "${M2D_LIBRARIES_ROOT}"/container.sh || return "${RC_ERROR}"
source "${M2D_LIBRARIES_ROOT}"/env.sh || return "${RC_ERROR}"
source "${M2D_LIBRARIES_ROOT}"/message.sh || return "${RC_ERROR}"
source "${M2D_LIBRARIES_ROOT}"/systemRequirements.sh || return "${RC_ERROR}"

readonly _SERVICES_DOCKER_HUB_API="https://hub.docker.com/v2/namespaces"

# Services started when no -s option is given.
readonly SERVICES_DEFAULT="mariadb,opensearch,redis"

# Service group: services of a group are mutually exclusive.
declare -grA _SERVICES_GROUP=(
    [mariadb]=DB_ENGINE
    [mysql]=DB_ENGINE
    [opensearch]=SEARCH_ENGINE
    [elasticsearch]=SEARCH_ENGINE
    [redis]=DB_CACHE
    [valkey]=DB_CACHE
    [rabbitmq]=MESSAGE_BROKER
    [varnish]=WEB_CACHE
    [mailcatcher]=MAILCATCHER
    [blackfire]=BLACKFIRE
    [selenium]=SELENIUM
)

# Groups saved to the .env file, in output order.
readonly _SERVICES_GROUPS="DB_ENGINE SEARCH_ENGINE DB_CACHE MESSAGE_BROKER WEB_CACHE MAILCATCHER BLACKFIRE SELENIUM"

# Service name in the system requirements matrix.
declare -grA _SERVICES_MATRIX_KEY=(
    [mariadb]=MariaDB
    [mysql]=MySQL
    [opensearch]=OpenSearch
    [elasticsearch]=Elasticsearch
    [redis]=Redis
    [valkey]=Valkey
    [rabbitmq]=RabbitMQ
    [varnish]=Varnish
)

# Docker Hub repository of the service image.
declare -grA _SERVICES_REPOSITORY=(
    [mariadb]=mariadb
    [mysql]=mysql
    [opensearch]=opensearchproject/opensearch
    [elasticsearch]=elasticsearch
    [redis]=redis
    [valkey]=valkey/valkey
    [rabbitmq]=rabbitmq
    [varnish]=varnish
)

# Suffix of the service image tag.
declare -grA _SERVICES_TAG_SUFFIX=(
    [rabbitmq]=-management
)

# PHP versions the web server image can be built with.
readonly _SERVICES_PHP_VERSIONS="7.3 7.4 8.0 8.1 8.2 8.3 8.4 8.5"

###########################################################
# Makes sure the system requirements matrix holds a
# Commerce version, downloading the matrix when missing.
# Arguments:
#   commerceVersion, (string) Normalized Commerce version
# Returns:
#   RC_OK on success
#   RC_ERROR if the version is unknown or in case of error
###########################################################
services::_ensureMatrix() {
    local -r commerceVersion="${1:?commerceVersion is not set}"
    local versions

    versions=$(systemRequirements::versions) || return "${RC_ERROR}"
    if ! grep -Fxq -- "${commerceVersion}" <<<"${versions}"; then
        message::notice "Commerce ${commerceVersion} is not in the system requirements matrix; downloading the latest matrix."
        systemRequirements::update || return "${RC_ERROR}"
        versions=$(systemRequirements::versions) || return "${RC_ERROR}"
    fi
    grep -Fxq -- "${commerceVersion}" <<<"${versions}" || {
        message::error "Unknown Commerce version '${commerceVersion}'. Latest known versions: $(head -n 10 <<<"${versions}" | tr '\n' ' ')"
        return "${RC_ERROR}"
    }
}

###########################################################
# Outputs the highest version of a requirement value.
# Arguments:
#   value, (string) Requirement value, e.g. "8.4, 8.3",
#          "7.17/8" or "12.3 (recommended), 11.8"
# Outputs:
#   Highest version to stdout, e.g. 8.4
# Returns:
#   RC_OK on success
#   RC_NO if the value holds no version
###########################################################
services::_highestVersion() {
    local -r value="${1:-}"
    local token tokens versions=()

    IFS=',/' read -ra tokens <<<"${value}"
    for token in "${tokens[@]}"; do
        [[ "${token}" =~ ^[[:space:]]*([0-9]+(\.[0-9]+)*) ]] && versions+=("${BASH_REMATCH[1]}")
    done
    ((${#versions[@]} > 0)) || return "${RC_NO}"

    printf '%s\n' "${versions[@]}" | sort -V | tail -n 1
}

###########################################################
# Parses the service list options into a comma separated
# list of selected services.
# Arguments:
#   ..., (string) Service lists, e.g. "mariadb,redis"
# Outputs:
#   Selected services to stdout, one per line
# Returns:
#   RC_OK on success
#   RC_ERROR if a service is unknown or two services of
#   the same group are selected
###########################################################
services::_parse() {
    local list service names
    local -A selected=()

    for list in "$@"; do
        IFS=',' read -ra names <<<"${list}"
        for service in "${names[@]}"; do
            service="${service//[[:space:]]/}"
            service="${service,,}"
            [[ -z "${service}" || "${service}" == 'web' ]] && continue
            [[ -n "${_SERVICES_GROUP[${service}]:-}" ]] || {
                message::error "Unknown service '${service}'. Expected one of: $(services::list | tr '\n' ' ')"
                return "${RC_ERROR}"
            }
            local group="${_SERVICES_GROUP[${service}]}"
            if [[ -n "${selected[${group}]:-}" && "${selected[${group}]}" != "${service}" ]]; then
                message::error "Services '${selected[${group}]}' and '${service}' cannot run together."
                return "${RC_ERROR}"
            fi
            selected[${group}]="${service}"
        done
    done

    for group in ${_SERVICES_GROUPS}; do
        [[ -n "${selected[${group}]:-}" ]] && printf '%s\n' "${selected[${group}]}"
    done
    return "${RC_OK}"
}

###########################################################
# Resolves the matrix version of a service for a Commerce
# version. Redis falls back to Valkey on Commerce versions
# that only support Valkey.
# Arguments:
#   commerceVersion, (string) Commerce version
#   service,         (string) Service, e.g. mariadb
# Outputs:
#   "service<TAB>version" to stdout, e.g. "valkey	8.1"
# Returns:
#   RC_OK on success
#   RC_ERROR if the service is not supported
###########################################################
services::_requirement() {
    local -r commerceVersion="${1:?commerceVersion is not set}"
    local service="${2:?service is not set}"
    local value version rc=0

    value=$(systemRequirements::get "${commerceVersion}" "${_SERVICES_MATRIX_KEY[${service}]}") || rc=$?
    if ((rc == RC_NO)) && [[ "${service}" == 'redis' ]]; then
        rc=0
        value=$(systemRequirements::get "${commerceVersion}" "${_SERVICES_MATRIX_KEY[valkey]}") || rc=$?
        ((rc == RC_OK)) && {
            message::notice "Commerce ${commerceVersion} does not support Redis; using Valkey instead."
            service='valkey'
        }
    fi
    ((rc == RC_ERROR)) && return "${RC_ERROR}"
    ((rc == RC_OK)) || {
        message::error "Commerce ${commerceVersion} does not support ${_SERVICES_MATRIX_KEY[${service}]}."
        return "${RC_ERROR}"
    }

    version=$(services::_highestVersion "${value}") || {
        message::error "No ${_SERVICES_MATRIX_KEY[${service}]} version found in '${value}' for Commerce ${commerceVersion}."
        return "${RC_ERROR}"
    }
    printf '%s\t%s\n' "${service}" "${version}"
}

###########################################################
# Resolves the service versions of a Commerce version and
# saves them to the .env file.
# Arguments:
#   projectPath,     (string) m2d project directory
#   commerceVersion, (string) Commerce version, e.g. 248p5
#   ...,             (string) Selected services
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
services::configure() {
    local -r projectPath="${1:?projectPath is not set}"
    local -r envFile="${projectPath}/.env"
    local commerceVersion service group requirement version image php
    shift
    commerceVersion=$(services::normalizeVersion "${1:-}") || return "${RC_ERROR}"
    shift

    services::_ensureMatrix "${commerceVersion}" || return "${RC_ERROR}"
    if [[ ! -f "${envFile}" ]]; then
        cp "${envFile}.example" "${envFile}" || return "${RC_ERROR}"
        message::notice "Created ${envFile} from ${envFile}.example. Run \`m2d setup env\` to review the core settings."
    fi

    local -A enabled=()
    local -A lines=()
    for service in "$@"; do
        group="${_SERVICES_GROUP[${service}]}"
        enabled[${group}]=yes
        [[ -n "${_SERVICES_MATRIX_KEY[${service}]:-}" ]] || continue

        requirement=$(services::_requirement "${commerceVersion}" "${service}") || return "${RC_ERROR}"
        IFS=$'\t' read -r service version <<<"${requirement}"
        image=$(services::image "${service}" "${version}") || return "${RC_ERROR}"
        lines[${group}]="${service}"$'\t'"${version}"$'\t'"${image}"
    done

    php=$(systemRequirements::get "${commerceVersion}" PHP) && php=$(services::_highestVersion "${php}") || {
        message::error "No PHP version found for Commerce ${commerceVersion}."
        return "${RC_ERROR}"
    }
    [[ " ${_SERVICES_PHP_VERSIONS} " == *" ${php} "* ]] || {
        message::error "PHP ${php} is not supported by the web server image. Supported versions: ${_SERVICES_PHP_VERSIONS}"
        return "${RC_ERROR}"
    }

    env::setParameter "${envFile}" M2D_COMMERCE_VERSION "${commerceVersion}" || return "${RC_ERROR}"
    env::setParameter "${envFile}" M2D_WEB_SERVER_PHP_VERSION "${php}" || return "${RC_ERROR}"
    env::setParameter "${envFile}" M2D_WEB_SERVER_OS "$(services::webServerOs "${php}")" || return "${RC_ERROR}"
    message::notice "Commerce ${commerceVersion}: web (PHP ${php})"

    local vendor
    for group in ${_SERVICES_GROUPS}; do
        env::setParameter "${envFile}" "M2D_ENABLE_${group}" "${enabled[${group}]:-no}" || return "${RC_ERROR}"
        [[ -n "${lines[${group}]:-}" ]] || continue
        IFS=$'\t' read -r vendor version image <<<"${lines[${group}]}"
        env::setParameter "${envFile}" "M2D_${group}_VENDOR" "${vendor}" || return "${RC_ERROR}"
        env::setParameter "${envFile}" "M2D_${group}_VERSION" "${version}" || return "${RC_ERROR}"
        env::setParameter "${envFile}" "M2D_${group}_IMAGE" "${image}" || return "${RC_ERROR}"
        message::notice "Commerce ${commerceVersion}: ${vendor} (${image})"
    done
    for service in mailcatcher blackfire selenium; do
        [[ -n "${enabled[${_SERVICES_GROUP[${service}]}]:-}" ]] && message::notice "Commerce ${commerceVersion}: ${service}"
    done
    return "${RC_OK}"
}

###########################################################
# Resolves the Docker image of a service version. The
# exact tag is used when it exists, otherwise the highest
# tag of the version, e.g. elasticsearch 8 resolves to
# elasticsearch:8.19.x. The exact tag is used without
# verification when Docker Hub cannot be reached.
# Arguments:
#   service, (string) Service, e.g. elasticsearch
#   version, (string) Version, e.g. 8
# Outputs:
#   Image to stdout, e.g. elasticsearch:8.19.2
# Returns:
#   RC_OK on success
#   RC_ERROR if no tag matches the version
###########################################################
services::image() {
    local -r service="${1:?service is not set}"
    local -r version="${2:?version is not set}"
    local -r repository="${_SERVICES_REPOSITORY[${service}]:-}"
    local -r suffix="${_SERVICES_TAG_SUFFIX[${service}]:-}"
    local namespace="library" name="${repository}" api code tags tag

    [[ -n "${repository}" ]] || {
        message::error "Service '${service}' has no Docker image."
        return "${RC_ERROR}"
    }
    [[ "${repository}" == */* ]] && {
        namespace="${repository%%/*}"
        name="${repository#*/}"
    }
    api="${_SERVICES_DOCKER_HUB_API}/${namespace}/repositories/${name}/tags"

    if ! command -v curl &>/dev/null || ! command -v jq &>/dev/null; then
        message::warning "curl and jq are required to verify the ${repository} tags; using ${repository}:${version}${suffix}."
        printf '%s:%s\n' "${repository}" "${version}${suffix}"
        return "${RC_OK}"
    fi

    code=$(curl -s -o /dev/null -w '%{http_code}' "${api}/${version}${suffix}")
    case "${code}" in
        200)
            printf '%s:%s\n' "${repository}" "${version}${suffix}"
            return "${RC_OK}"
            ;;
        404)
            ;;
        *)
            message::warning "Docker Hub is unreachable; using ${repository}:${version}${suffix} without verification."
            printf '%s:%s\n' "${repository}" "${version}${suffix}"
            return "${RC_OK}"
            ;;
    esac

    tags=$(curl -fsS "${api}?name=${version}.&page_size=100&ordering=last_updated") || {
        message::error "Failed to list the ${repository} tags from Docker Hub."
        return "${RC_ERROR}"
    }
    tag=$(jq -r '.results[].name' <<<"${tags}" |
        grep -E "^${version//./\\.}(\\.[0-9]+)+${suffix}\$" |
        sort -V | tail -n 1)
    [[ -n "${tag}" ]] || {
        message::error "No ${repository} image found for version ${version}."
        return "${RC_ERROR}"
    }
    printf '%s:%s\n' "${repository}" "${tag}"
}

###########################################################
# Lists the services that can be selected with -s.
# Outputs:
#   One service per line to stdout
###########################################################
services::list() {
    printf '%s\n' mariadb mysql opensearch elasticsearch redis valkey rabbitmq varnish mailcatcher blackfire selenium
}

###########################################################
# Normalizes a Commerce version.
# Arguments:
#   version, (string) Commerce version, e.g. 2.4.8-p5 or
#            248p5
# Outputs:
#   Normalized version to stdout, e.g. 2.4.8-p5
# Returns:
#   RC_OK on success
#   RC_ERROR if the version is invalid
###########################################################
services::normalizeVersion() {
    local -r version="${1:-}"

    if [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(p[0-9]+|[a-z]+[0-9]*))?$ ]]; then
        printf '%s\n' "${version}"
    elif [[ "${version}" =~ ^([0-9])([0-9])([0-9]+)(p([0-9]+))?$ ]]; then
        printf '%s.%s.%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
            "${BASH_REMATCH[5]:+-p${BASH_REMATCH[5]}}"
    else
        message::error "Invalid Commerce version '${version}'. Expected e.g. 2.4.8-p5 or 248p5."
        return "${RC_ERROR}"
    fi
}

###########################################################
# Configures and starts the stack of a Commerce version.
# Arguments:
#   projectPath, (string) m2d project directory
#   version,     (string) Commerce version
#   ...,         Options: -s|--services <list>
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
services::run() {
    local -r projectPath="${1:?projectPath is not set}"
    local -r version="${2:-}"
    local lists=() selected
    shift 2

    while (($# > 0)); do
        case "$1" in
            '-s' | '--services')
                [[ -n "${2:-}" ]] || {
                    message::error "Option '$1' requires a service list."
                    return "${RC_ERROR}"
                }
                lists+=("$2")
                shift 2
                ;;
            -s*)
                lists+=("${1#-s}")
                shift
                ;;
            *)
                message::error "Unknown option '$1'. Run \`m2d ${version} --help\` for usage."
                return "${RC_ERROR}"
                ;;
        esac
    done
    ((${#lists[@]} > 0)) || lists=("${SERVICES_DEFAULT}")

    selected=$(services::_parse "${lists[@]}") || return "${RC_ERROR}"
    local -a services=()
    [[ -n "${selected}" ]] && mapfile -t services <<<"${selected}"

    services::configure "${projectPath}" "${version}" "${services[@]}" || return "${RC_ERROR}"
    # Build args change with the Commerce version, so the images are rebuilt.
    container::up "${projectPath}" --build
}

###########################################################
# Outputs the Debian release of the PHP Apache image.
# PHP 8.4 and later images are not built on bullseye.
# Arguments:
#   phpVersion, (string) PHP version, e.g. 8.4
# Outputs:
#   Debian release to stdout, e.g. bookworm
###########################################################
services::webServerOs() {
    local -r phpVersion="${1:?phpVersion is not set}"

    if [[ "$(printf '%s\n' 8.4 "${phpVersion}" | sort -V | head -n 1)" == '8.4' ]]; then
        printf 'bookworm\n'
    else
        printf 'bullseye\n'
    fi
}
