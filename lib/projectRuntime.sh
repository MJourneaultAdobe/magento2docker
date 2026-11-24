#!/usr/bin/env bash
# shellcheck shell=bash

source "$(dirname -- "${BASH_SOURCE[0]}")/message.sh" || return 255
source "${M2D_LIBRARIES_ROOT}/services.sh" || return "${RC_ERROR}"

projectRuntime::_canonicalService() {
  case "${1,,}" in
    mariadb|mysql|opensearch|elasticsearch|redis|valkey|rabbitmq|web|varnish|mailcatcher|blackfire|selenium) printf '%s\n' "${1,,}" ;;
    db) printf '%s\n' mariadb ;;
    search-engine|search_engine) printf '%s\n' opensearch ;;
    elastic|es) printf '%s\n' elasticsearch ;;
    db-cache|db_cache) printf '%s\n' redis ;;
    message-broker|message_broker|rabbit) printf '%s\n' rabbitmq ;;
    web-cache|web_cache) printf '%s\n' varnish ;;
    m) printf '%s\n' mailcatcher ;;
    php) printf '%s\n' web ;;
    *) message::error "Unknown service '$1'. Use --help to list supported services."; return "${RC_ERROR}" ;;
  esac
}

projectRuntime::_cleanup() {
  [[ -z "${projectTemporaryFile:-}" ]] || rm -f -- "${projectTemporaryFile}"
  [[ -z "${projectLock:-}" ]] || rmdir -- "${projectLock}"
}

projectRuntime::_compose() {
  docker compose --project-directory "${projectDirectory}" --project-name "${projectName}" \
    --env-file "${projectState}/compose.env" -f "${projectState}/compose.json" "$@" || {
    message::error "Docker Compose failed. Settings are retained in ${projectFile}."
    return "${RC_ERROR}"
  }
}

projectRuntime::_configure() {
  local service version image requirement port database username password rootPassword managementPort
  local httpsPort sshPort ideKey publicKey privateKey cloudToken gitName gitEmail config sourceDirectory os memoryLimit
  local serverId serverToken clientId clientToken smtpPort vncPort
  local -a selected=()
  if jq -e '. as $settings | any(.services[]; $settings.serviceSettings[.] == null)' <<< "${projectSettings}" >/dev/null; then
    services::_ensureMatrix "${projectVersion}" || return "${RC_ERROR}"
  fi
  mapfile -t selected < <(jq -r '.services[]' <<< "${projectSettings}")
  for service in "${selected[@]}"; do
    if jq -e --arg service "${service}" '.serviceSettings[$service] != null' <<< "${projectSettings}" >/dev/null; then
      continue
    fi
    case "${service}" in
      web)
        version="$(systemRequirements::get "${projectVersion}" PHP)" &&
          version="$(services::_highestVersion "${version}")" || return "${RC_ERROR}" ;;
      mailcatcher|blackfire) version=latest ;;
      selenium) version=3.14.0 ;;
      *)
        requirement="$(services::_requirement "${projectVersion}" "${service}")" || return "${RC_ERROR}"
        IFS=$'\t' read -r image version <<< "${requirement}"
        if [[ "${image}" != "${service}" ]]; then
          projectSettings="$(jq --arg from "${service}" --arg to "${image}" '.services |= map(if . == $from then $to else . end)' <<< "${projectSettings}")" || return "${RC_ERROR}"
          service="${image}"
          if jq -e --arg service "${service}" '.serviceSettings[$service] != null' <<< "${projectSettings}" >/dev/null; then
            continue
          fi
        fi ;;
    esac
    projectRuntime::_prompt version "${service} version" "${version}" tag || return "${RC_ERROR}"
    case "${service}" in
      web) image="${projectName}-web:php-${version}" ;;
      mailcatcher) image="schickling/mailcatcher:${version}" ;;
      blackfire) image="blackfire/blackfire:${version}" ;;
      selenium) image="selenium/standalone-chrome-debug:${version}" ;;
      *) image="$(services::image "${service}" "${version}")" || return "${RC_ERROR}" ;;
    esac
    case "${service}" in
      mariadb|mysql)
        projectRuntime::_prompt port "${service} host port" 3306 port &&
          projectRuntime::_prompt database "Database name" magento identifier &&
          projectRuntime::_prompt username "Database user (not root)" magento username &&
          projectRuntime::_prompt password "Database password" "" secret &&
          projectRuntime::_prompt rootPassword "Database root password" "" secret || return "${RC_ERROR}"
        config="$(jq -n --arg version "${version}" --arg port "${port}" --arg database "${database}" \
          --arg username "${username}" --arg password "${password}" --arg rootPassword "${rootPassword}" \
          '$ARGS.named')" || return "${RC_ERROR}"
        ;;
      opensearch|elasticsearch)
        projectRuntime::_prompt port "${service} host port (local HTTP; security disabled)" 9200 port || return "${RC_ERROR}"
        config="$(jq -n --arg version "${version}" --arg port "${port}" '$ARGS.named')" || return "${RC_ERROR}"
        ;;
      redis|valkey)
        projectRuntime::_prompt port "${service} host port" 6379 port &&
          projectRuntime::_prompt password "${service} password" "" secret || return "${RC_ERROR}"
        config="$(jq -n --arg version "${version}" --arg port "${port}" --arg password "${password}" '$ARGS.named')" || return "${RC_ERROR}"
        ;;
      rabbitmq)
        projectRuntime::_prompt port "RabbitMQ host port" 5672 port &&
          projectRuntime::_prompt managementPort "RabbitMQ management host port" 15672 port &&
          projectRuntime::_prompt username "RabbitMQ user" magento identifier &&
          projectRuntime::_prompt password "RabbitMQ password" "" secret || return "${RC_ERROR}"
        config="$(jq -n --arg version "${version}" --arg port "${port}" --arg managementPort "${managementPort}" \
          --arg username "${username}" --arg password "${password}" '$ARGS.named')" || return "${RC_ERROR}"
        ;;
      varnish)
        projectRuntime::_prompt port "Varnish HTTP host port" 8080 port || return "${RC_ERROR}"
        config="$(jq -n --arg version "${version}" --arg port "${port}" '$ARGS.named')" || return "${RC_ERROR}" ;;
      mailcatcher)
        projectRuntime::_prompt port "Mailcatcher web host port" 1080 port &&
          projectRuntime::_prompt smtpPort "Mailcatcher SMTP host port" 1025 port || return "${RC_ERROR}"
        config="$(jq -n --arg version "${version}" --arg port "${port}" --arg smtpPort "${smtpPort}" '$ARGS.named')" || return "${RC_ERROR}" ;;
      blackfire)
        projectRuntime::_prompt port "Blackfire agent host port" 8707 port &&
          projectRuntime::_prompt serverId "Blackfire server ID" "" required &&
          projectRuntime::_prompt serverToken "Blackfire server token" "" secret &&
          projectRuntime::_prompt clientId "Blackfire client ID" "" required &&
          projectRuntime::_prompt clientToken "Blackfire client token" "" secret || return "${RC_ERROR}"
        config="$(jq -n --arg version "${version}" --arg port "${port}" --arg serverId "${serverId}" \
          --arg serverToken "${serverToken}" --arg clientId "${clientId}" --arg clientToken "${clientToken}" '$ARGS.named')" || return "${RC_ERROR}" ;;
      selenium)
        projectRuntime::_prompt port "Selenium host port" 4444 port &&
          projectRuntime::_prompt vncPort "Selenium VNC host port" 5900 port || return "${RC_ERROR}"
        config="$(jq -n --arg version "${version}" --arg port "${port}" --arg vncPort "${vncPort}" '$ARGS.named')" || return "${RC_ERROR}" ;;
      web)
        projectRuntime::_prompt sourceDirectory "Source directory to bind into /var/www/html" "${projectDirectory}" path &&
          projectRuntime::_prompt port "Web HTTP host port" 80 port &&
          projectRuntime::_prompt httpsPort "Web HTTPS host port" 443 port &&
          projectRuntime::_prompt sshPort "Web SSH host port" 2222 port &&
          projectRuntime::_prompt ideKey "Xdebug IDE key" PHPSTORM identifier &&
          projectRuntime::_prompt memoryLimit "PHP memory limit" 2G memory &&
          projectRuntime::_prompt publicKey "Composer public key (optional)" "" optional &&
          projectRuntime::_prompt privateKey "Composer private key (optional)" "" optionalSecret &&
          projectRuntime::_prompt cloudToken "Commerce Cloud CLI token (optional)" "" optionalSecret &&
          projectRuntime::_prompt gitName "Git user name (optional)" "" optional &&
          projectRuntime::_prompt gitEmail "Git email (optional)" "" optional || return "${RC_ERROR}"
        if [[ -n "${publicKey}" && -z "${privateKey}" || -z "${publicKey}" && -n "${privateKey}" ]]; then
          message::error "Supply both Composer keys or leave both empty."
          return "${RC_ERROR}"
        fi
        mkdir -p -- "${sourceDirectory}" || {
          message::error "Cannot create source directory '${sourceDirectory}'."
          return "${RC_ERROR}"
        }
        sourceDirectory="$(cd -- "${sourceDirectory}" && pwd -P)" || return "${RC_ERROR}"
        os="$(services::webServerOs "${version}")" || return "${RC_ERROR}"
        projectSettings="$(jq --arg sourceDirectory "${sourceDirectory}" '.sourceDirectory = $sourceDirectory' <<< "${projectSettings}")" || return "${RC_ERROR}"
        config="$(jq -n --arg version "${version}" --arg port "${port}" --arg httpsPort "${httpsPort}" \
          --arg sshPort "${sshPort}" --arg ideKey "${ideKey}" --arg os "${os}" --arg memoryLimit "${memoryLimit}" --arg publicKey "${publicKey}" \
          --arg privateKey "${privateKey}" --arg cloudToken "${cloudToken}" --arg gitName "${gitName}" \
          --arg gitEmail "${gitEmail}" '$ARGS.named')" || return "${RC_ERROR}"
        ;;
    esac
    projectSettings="$(jq --arg service "${service}" --arg image "${image}" --argjson config "${config}" \
      '.serviceSettings[$service] = ($config + {image:$image}) | .setupComplete = false' <<< "${projectSettings}")" || return "${RC_ERROR}"
  done
}

projectRuntime::_help() {
  cat <<'EOM'
Usage: m2d [COMMERCE_VERSION] [-s SERVICES]
       m2d COMMAND [OPTIONS]

First run prompts for project configuration and credentials, saves
./.m2d/settings.json, pulls service images, and starts healthy containers.
Later runs of m2d reuse the saved settings without prompting.

Examples:
  m2d 2.4.8-p5
  m2d 248p5 -s mariadb,opensearch,valkey,web
  m2d

Options:
  -s, --services LIST  Comma-separated services; repeatable. Replaces the saved selection.
  -h, --help           Show this help.

Services:
  mariadb, mysql, opensearch, elasticsearch, redis, valkey, rabbitmq, web
  varnish, mailcatcher, blackfire, selenium
  Default: mariadb,opensearch,redis. Web is built locally only when selected.
  Redis resolves to Valkey where required by the Commerce requirements matrix.
  Varnish also selects web as its backend.

Commands:
  up [--build]         Start services (alias for m2d; --build rebuilds web).
  setup init           Configure and start services (compatibility alias).
  down                 Remove project containers and network, preserving volumes.
  stop                 Stop project containers.
  build                Pull service images and build web when selected.
  go SERVICE [USER]    Open a shell in a running service.
  logs [SERVICE]       Follow project logs.
  show PARAMETER       Show a non-secret setting (home, src, version, services).
  set PARAMETER VALUE  Set a saved port, source path, PHP version, or IDE key.
  enable SERVICE       Add a service to the saved selection.
  disable SERVICE      Remove a service from the saved selection.
  sync                 Sources are bind-mounted; no separate sync is needed.
EOM
}

projectRuntime::_load() {
  projectSettings="$(cat -- "${projectFile}")" || {
    message::error "Cannot read ${projectFile}."
    return "${RC_ERROR}"
  }
  projectRuntime::_validate || return "${RC_ERROR}"
  projectVersion="$(jq -r '.commerceVersion' <<< "${projectSettings}")" || return "${RC_ERROR}"
  projectName="$(jq -r '.projectName' <<< "${projectSettings}")" || return "${RC_ERROR}"
}

projectRuntime::_normalizeVersion() {
  services::normalizeVersion "${1}"
}

projectRuntime::_parameterPath() {
  local parameter="${1}" service
  case "${parameter}" in
    src|M2D_SOURCE_DIRECTORY) printf '%s\n' '["sourceDirectory"]'; return ;;
    php|M2D_WEB_SERVER_PHP_VERSION) service=web; parameter=version ;;
    M2D_XDEBUG_IDE_KEY) service=web; parameter=ideKey ;;
    M2D_WEB_SERVER_PHP_MEMORY_LIMIT) service=web; parameter=memoryLimit ;;
    M2D_PORT_FOR_WEB_SERVER_HTTP) service=web; parameter=port ;;
    M2D_PORT_FOR_WEB_SERVER_HTTPS) service=web; parameter=httpsPort ;;
    M2D_PORT_FOR_WEB_SERVER_SSH) service=web; parameter=sshPort ;;
    M2D_PORT_FOR_DB_ENGINE) service="$(jq -r '.services[] | select(. == "mariadb" or . == "mysql")' <<< "${projectSettings}")"; parameter=port ;;
    M2D_PORT_FOR_SEARCH_ENGINE) service="$(jq -r '.services[] | select(. == "opensearch" or . == "elasticsearch")' <<< "${projectSettings}")"; parameter=port ;;
    M2D_PORT_FOR_DB_CACHE) service="$(jq -r '.services[] | select(. == "redis" or . == "valkey")' <<< "${projectSettings}")"; parameter=port ;;
    M2D_PORT_FOR_MESSAGE_BROKER) service=rabbitmq; parameter=managementPort ;;
    M2D_PORT_FOR_WEB_CACHE) service=varnish; parameter=port ;;
    M2D_PORT_FOR_MAILCATCHER) service=mailcatcher; parameter=port ;;
    M2D_PORT_FOR_SELENIUM_HUB) service=selenium; parameter=port ;;
    M2D_PORT_FOR_SELENIUM_VNC) service=selenium; parameter=vncPort ;;
    *) message::error "Unsupported setting '${parameter}' in project settings."; return "${RC_ERROR}" ;;
  esac
  if [[ -z "${service}" ]] || ! jq -e --arg service "${service}" '.serviceSettings[$service] != null' <<< "${projectSettings}" >/dev/null; then
    message::error "Configure the corresponding service before changing '${1}'."
    return "${RC_ERROR}"
  fi
  jq -nc --arg service "${service}" --arg parameter "${parameter}" '["serviceSettings", $service, $parameter]'
}

projectRuntime::_prompt() {
  local target="${1}" label="${2}" default="${3}" kind="${4}" answer
  if [[ ! -t 0 ]]; then
    message::error "First-run configuration requires an interactive terminal (${label})."
    return "${RC_ERROR}"
  fi
  while true; do
    if [[ "${kind}" == secret || "${kind}" == optionalSecret ]]; then
      printf '%s: ' "${label}" >&2
      IFS= read -rs answer || { printf '\n' >&2; message::error "Configuration cancelled."; return "${RC_ERROR}"; }
      printf '\n' >&2
    else
      printf '%s%s: ' "${label}" "${default:+ [${default}]}" >&2
      IFS= read -r answer || { message::error "Configuration cancelled."; return "${RC_ERROR}"; }
    fi
    answer="${answer:-${default}}"
    if [[ -z "${answer}" && "${kind}" != optional && "${kind}" != optionalSecret ]]; then
      message::error "A value is required for ${label}."
      continue
    fi
    case "${kind}" in
      port)
        if [[ ! "${answer}" =~ ^[0-9]{1,5}$ ]] || (( 10#${answer} < 1 || 10#${answer} > 65535 )); then
          message::error "Port must be between 1 and 65535."
          continue
        fi
        answer="$((10#${answer}))"
        ;;
      tag)
        [[ "${answer}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || { message::error "Invalid image version."; continue; }
        ;;
      memory)
        [[ "${answer}" =~ ^[1-9][0-9]*[KMG]?$ ]] || { message::error "Use a positive PHP memory limit such as 2G."; continue; }
        ;;
      identifier|username)
        [[ "${answer}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || { message::error "Use letters, digits, underscores, dots or hyphens."; continue; }
        [[ "${kind}" != username || "${answer}" != root ]] || { message::error "Use a non-root database user."; continue; }
        ;;
      projectName)
        [[ "${answer}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { message::error "Use lowercase letters, digits, underscores or hyphens."; continue; }
        ;;
      path)
        case "${answer}" in '~') answer="${HOME}" ;; '~/'*) answer="${HOME}/${answer#\~/}" ;; esac
        [[ "${answer}" == /* ]] || answer="${projectDirectory}/${answer}"
        ;;
    esac
    printf -v "${target}" '%s' "${answer}"
    return "${RC_OK}"
  done
}

projectRuntime::_render() {
  local auth
  projectTemporaryFile="$(mktemp "${projectState}/compose.XXXXXX")" || return "${RC_ERROR}"
  if ! jq --arg installation "$(dirname -- "${M2D_LIBRARIES_ROOT}")" --arg state "${projectState}" \
    -f "${M2D_LIBRARIES_ROOT}/projectCompose.jq" <<< "${projectSettings}" > "${projectTemporaryFile}" ||
    ! mv -- "${projectTemporaryFile}" "${projectState}/compose.json"; then
    message::error "Cannot generate project Compose configuration."
    return "${RC_ERROR}"
  fi
  projectTemporaryFile=""
  : > "${projectState}/compose.env" || return "${RC_ERROR}"
  if jq -e '.services | index("web") != null' <<< "${projectSettings}" >/dev/null; then
    auth="$(jq '.serviceSettings.web |
      if .publicKey == "" then {} else {"http-basic":{"repo.magento.com":{"username":.publicKey,"password":.privateKey}}} end' \
      <<< "${projectSettings}")" || return "${RC_ERROR}"
    printf '%s\n' "${auth}" > "${projectState}/auth.json" || return "${RC_ERROR}"
    : > "${projectState}/gitconfig" || return "${RC_ERROR}"
    git config --file "${projectState}/gitconfig" user.name "$(jq -r '.serviceSettings.web.gitName' <<< "${projectSettings}")" &&
      git config --file "${projectState}/gitconfig" user.email "$(jq -r '.serviceSettings.web.gitEmail' <<< "${projectSettings}")" || {
      message::error "Cannot generate project Git configuration."
      return "${RC_ERROR}"
    }
  fi
  projectRuntime::_compose config --quiet
}

projectRuntime::_save() {
  projectRuntime::_validate || return "${RC_ERROR}"
  projectTemporaryFile="$(mktemp "${projectState}/settings.XXXXXX")" || {
    message::error "Cannot create temporary settings file."
    return "${RC_ERROR}"
  }
  if ! printf '%s\n' "${projectSettings}" > "${projectTemporaryFile}" ||
    ! chmod 600 "${projectTemporaryFile}" || ! mv -- "${projectTemporaryFile}" "${projectFile}"; then
    message::error "Cannot save ${projectFile}."
    return "${RC_ERROR}"
  fi
  projectTemporaryFile=""
}

projectRuntime::_selectServices() {
  local input="${1}" service canonical services='[]'
  local -a requested=()
  IFS=', ' read -ra requested <<< "${input}"
  for service in "${requested[@]}"; do
    canonical="$(projectRuntime::_canonicalService "${service}")" || return "${RC_ERROR}"
    services="$(jq --arg service "${canonical}" 'if index($service) == null then . + [$service] else . end' <<< "${services}")" || return "${RC_ERROR}"
  done
  if jq -e 'index("varnish") != null and index("web") == null' <<< "${services}" >/dev/null; then
    message::notice "Selecting web as the Varnish backend."
    services="$(jq '. + ["web"]' <<< "${services}")" || return "${RC_ERROR}"
  fi
  if ! jq -e 'length > 0 and
    ([.[] | select(. == "mariadb" or . == "mysql")] | length <= 1) and
    ([.[] | select(. == "opensearch" or . == "elasticsearch")] | length <= 1) and
    ([.[] | select(. == "redis" or . == "valkey")] | length <= 1)' <<< "${services}" >/dev/null; then
    message::error "Select at least one service and only one database, search engine and cache engine."
    return "${RC_ERROR}"
  fi
  projectSettings="$(jq --argjson services "${services}" \
    'if .services == $services then . else .services = $services | .setupComplete = false end' <<< "${projectSettings}")"
}

projectRuntime::_start() {
  local rebuild="${1}" complete
  complete="$(jq -r '.setupComplete' <<< "${projectSettings}")" || return "${RC_ERROR}"
  if [[ "${complete}" != true || "${rebuild}" == true ]]; then
    projectRuntime::_compose pull --ignore-buildable || return "${RC_ERROR}"
    projectRuntime::_compose up -d --build --remove-orphans --wait --wait-timeout 180 || return "${RC_ERROR}"
  else
    projectRuntime::_compose up -d --remove-orphans --wait --wait-timeout 180 || return "${RC_ERROR}"
  fi
  projectSettings="$(jq '.setupComplete = true' <<< "${projectSettings}")" || return "${RC_ERROR}"
  projectRuntime::_save || return "${RC_ERROR}"
  message::notice "Services are ready. Run m2d from ${projectDirectory} to start them again."
}

projectRuntime::_validate() {
  if ! jq -e '
    def nonempty: type == "string" and length > 0;
    def port: type == "string" and test("^[0-9]{1,5}$") and (tonumber >= 1 and tonumber <= 65535);
    . as $settings |
    .schemaVersion == 1 and
    (.commerceVersion | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+(-(p[0-9]+|[a-z]+[0-9]*))?$")) and
    (.projectName | type == "string" and test("^[a-z0-9][a-z0-9_-]*$")) and
    (.sourceDirectory | type == "string" and startswith("/")) and
    (.setupComplete | type == "boolean") and
    (.serviceSettings | type == "object") and
    (.services | type == "array" and length > 0 and length == (unique | length) and
      all(.[]; IN("mariadb", "mysql", "opensearch", "elasticsearch", "redis", "valkey", "rabbitmq", "web", "varnish", "mailcatcher", "blackfire", "selenium"))) and
    ((.services | index("varnish") == null) or (.services | index("web") != null)) and
    ([.services[] | select(. == "mariadb" or . == "mysql")] | length <= 1) and
    ([.services[] | select(. == "opensearch" or . == "elasticsearch")] | length <= 1) and
    ([.services[] | select(. == "redis" or . == "valkey")] | length <= 1) and
    all(.services[]; . as $name | $settings.serviceSettings[$name] |
      (.version | type == "string" and test("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$")) and
      (.image | nonempty) and
      (.port | port) and
      if $name == "mariadb" or $name == "mysql" then
        (.database | nonempty) and (.username | nonempty and . != "root") and (.password | nonempty) and (.rootPassword | nonempty)
      elif $name == "redis" or $name == "valkey" then (.password | nonempty)
      elif $name == "rabbitmq" then (.username | nonempty) and (.password | nonempty) and (.managementPort | port)
      elif $name == "mailcatcher" then (.smtpPort | port)
      elif $name == "blackfire" then (.serverId | nonempty) and (.serverToken | nonempty) and (.clientId | nonempty) and (.clientToken | nonempty)
      elif $name == "selenium" then (.vncPort | port)
      elif $name == "web" then
        (.version | IN("7.3","7.4","8.0","8.1","8.2","8.3","8.4","8.5")) and
        (.os | IN("bullseye","bookworm")) and
        (.memoryLimit | type == "string" and test("^[1-9][0-9]*[KMG]?$")) and
        (.httpsPort | port) and (.sshPort | port) and (.ideKey | nonempty) and
        (.publicKey | type == "string") and (.privateKey | type == "string") and
        ((.publicKey == "") == (.privateKey == "")) and
        (.cloudToken | type == "string") and (.gitName | type == "string") and (.gitEmail | type == "string")
      else true end)
  ' <<< "${projectSettings}" >/dev/null 2>&1; then
    message::error "Invalid or incomplete project settings in ${projectFile}."
    return "${RC_ERROR}"
  fi
  local ports
  ports="$(jq '[. as $settings | .services[] | $settings.serviceSettings[.] |
    .port, .managementPort, .httpsPort, .sshPort, .smtpPort, .vncPort |
    select(. != null) | tonumber]' <<< "${projectSettings}")" || return "${RC_ERROR}"
  if ! jq -e 'length == (unique | length)' <<< "${ports}" >/dev/null; then
    message::error "Each selected service endpoint must use a distinct host port."
    return "${RC_ERROR}"
  fi
}

projectRuntime::run() (
  local action=start requestedVersion="" requestedServices="" rebuild=false parameter="" value="" service
  local projectDirectory projectState projectFile projectName projectVersion projectSettings projectLock="" projectTemporaryFile=""
  local path selected status
  projectDirectory="$(pwd -P)" || return "${RC_ERROR}"
  projectState="${projectDirectory}/.m2d"
  projectFile="${projectState}/settings.json"
  while (( $# > 0 )); do
    case "${1}" in
      -h|--help) projectRuntime::_help; return "${RC_OK}" ;;
      -s|--services)
        (( $# >= 2 )) && [[ -n "${2}" && "${2}" != -* ]] || { message::error "-s requires a service list."; return "${RC_ERROR}"; }
        requestedServices+="${requestedServices:+,}${2}"; shift 2 ;;
      -s?*) requestedServices+="${requestedServices:+,}${1#-s}"; shift ;;
      up) shift ;;
      -b|--build) rebuild=true; shift ;;
      setup)
        [[ "${2:-}" == init || "${2:-}" == env ]] || { message::error "Use m2d or m2d setup init for setup."; return "${RC_ERROR}"; }
        shift 2 ;;
      down|stop|build|sync)
        [[ "${action}" == start ]] || { message::error "Specify only one command."; return "${RC_ERROR}"; }
        action="${1}"; shift ;;
      logs|go|show|set|enable|disable)
        [[ "${action}" == start ]] || { message::error "Specify only one command."; return "${RC_ERROR}"; }
        action="${1}"; shift
        parameter="${1:-}"; (( $# == 0 )) || shift
        if [[ "${action}" == set || "${action}" == go ]]; then
          value="${1:-}"; (( $# == 0 )) || shift
        fi ;;
      [0-9]*)
        [[ -z "${requestedVersion}" ]] || { message::error "Specify only one Commerce version."; return "${RC_ERROR}"; }
        requestedVersion="${1}"; shift ;;
      *) message::error "Unknown argument '${1}'. Use --help."; return "${RC_ERROR}" ;;
    esac
  done
  if [[ "${action}" != start && ( -n "${requestedVersion}" || -n "${requestedServices}" || "${rebuild}" == true ) ]]; then
    message::error "Version, service selection and --build options are only valid when starting services."
    return "${RC_ERROR}"
  fi
  command -v jq >/dev/null || { message::error "jq is required. Install it before running m2d."; return "${RC_ERROR}"; }
  docker compose version >/dev/null 2>&1 || { message::error "Docker Compose v2 is required."; return "${RC_ERROR}"; }
  [[ -z "${requestedVersion}" ]] || requestedVersion="$(projectRuntime::_normalizeVersion "${requestedVersion}")" || return "${RC_ERROR}"
  if [[ ! -f "${projectFile}" && "${action}" != start ]]; then
    message::error "No project settings. Run m2d from this project first."
    return "${RC_ERROR}"
  fi
  umask 077
  mkdir -p -- "${projectState}" && chmod 700 "${projectState}" || { message::error "Cannot secure ${projectState}."; return "${RC_ERROR}"; }
  printf '*\n' > "${projectState}/.gitignore" || return "${RC_ERROR}"
  if ! mkdir -- "${projectState}/lock" 2>/dev/null; then
    message::error "Another m2d process holds ${projectState}/lock. Remove it only if that process is no longer running."
    return "${RC_ERROR}"
  fi
  projectLock="${projectState}/lock"
  trap 'projectRuntime::_cleanup' EXIT
  trap 'exit 255' INT TERM HUP
  if [[ -f "${projectFile}" ]]; then
    projectRuntime::_load || return "${RC_ERROR}"
    if [[ -n "${requestedVersion}" && "${requestedVersion}" != "${projectVersion}" ]]; then
      message::error "This project uses Commerce ${projectVersion}. Use another project directory for ${requestedVersion} to avoid incompatible persistent data."
      return "${RC_ERROR}"
    fi
  else
    docker info >/dev/null 2>&1 || { message::error "Start Docker before configuring m2d."; return "${RC_ERROR}"; }
    if [[ -z "${requestedVersion}" ]]; then
      projectRuntime::_prompt requestedVersion "Commerce version (e.g. 2.4.8-p5 or 248p5)" "" required || return "${RC_ERROR}"
      requestedVersion="$(projectRuntime::_normalizeVersion "${requestedVersion}")" || return "${RC_ERROR}"
    fi
    projectVersion="${requestedVersion}"
    projectName="m2d-$(printf '%s' "${projectDirectory}" | cksum | cut -d ' ' -f 1)"
    projectRuntime::_prompt projectName "Docker Compose project name" "${projectName}" projectName || return "${RC_ERROR}"
    projectSettings="$(jq -n --arg version "${projectVersion}" --arg name "${projectName}" --arg source "${projectDirectory}" \
      '{schemaVersion:1, commerceVersion:$version, projectName:$name, sourceDirectory:$source,
        setupComplete:false, services:[], serviceSettings:{}}')" || return "${RC_ERROR}"
    requestedServices="${requestedServices:-mariadb,opensearch,redis}"
  fi
  if [[ -n "${requestedServices}" ]]; then
    projectRuntime::_selectServices "${requestedServices}" || return "${RC_ERROR}"
  fi
  case "${action}" in
    enable|disable)
      service="$(projectRuntime::_canonicalService "${parameter}")" || return "${RC_ERROR}"
      selected="$(jq -r --arg service "${service}" --arg action "${action}" \
        '(.services | if $action == "enable" then . + [$service] else map(select(. != $service)) end) | join(",")' <<< "${projectSettings}")" || return "${RC_ERROR}"
      projectRuntime::_selectServices "${selected}" &&
        projectRuntime::_configure && projectRuntime::_save || return "${RC_ERROR}"
      message::notice "Service selection saved. Run m2d to apply it."
      ;;
    show)
      case "${parameter}" in
        home) printf '%s\n' "$(dirname -- "${M2D_LIBRARIES_ROOT}")" ;;
        version) printf '%s\n' "${projectVersion}" ;;
        services) jq -r '.services | join(",")' <<< "${projectSettings}" ;;
        *) path="$(projectRuntime::_parameterPath "${parameter}")" &&
          jq -r --argjson path "${path}" 'getpath($path)' <<< "${projectSettings}" || return "${RC_ERROR}" ;;
      esac ;;
    set)
      [[ -n "${value}" ]] || { message::error "set requires a parameter and value."; return "${RC_ERROR}"; }
      path="$(projectRuntime::_parameterPath "${parameter}")" || return "${RC_ERROR}"
      if [[ "${path}" == '["sourceDirectory"]' ]]; then
        [[ "${value}" == /* ]] || value="${projectDirectory}/${value}"
        [[ -d "${value}" ]] || { message::error "Source directory does not exist."; return "${RC_ERROR}"; }
        value="$(cd -- "${value}" && pwd -P)" || return "${RC_ERROR}"
      fi
      projectSettings="$(jq --argjson path "${path}" --arg value "${value}" \
        'setpath($path; $value) | .setupComplete = false' <<< "${projectSettings}")" || return "${RC_ERROR}"
      if [[ "${parameter}" == php || "${parameter}" == M2D_WEB_SERVER_PHP_VERSION ]]; then
        projectSettings="$(jq --arg image "${projectName}-web:php-${value}" --arg os "$(services::webServerOs "${value}")" \
          '.serviceSettings.web.image = $image | .serviceSettings.web.os = $os' <<< "${projectSettings}")" || return "${RC_ERROR}"
      fi
      projectRuntime::_save ;;
    sync) message::notice "Project sources use a bind mount; no synchronization action is required." ;;
    *)
      if [[ "${action}" == start ]]; then
        projectRuntime::_configure && projectRuntime::_save || return "${RC_ERROR}"
      fi
      projectRuntime::_render || return "${RC_ERROR}"
      if [[ "${action}" == logs || "${action}" == go ]]; then
        projectRuntime::_cleanup
        projectLock=""
      fi
      case "${action}" in
        start) projectRuntime::_start "${rebuild}" ;;
        down|stop) projectRuntime::_compose "${action}" ;;
        build)
          projectRuntime::_compose pull --ignore-buildable || return "${RC_ERROR}"
          if jq -e '.services | index("web") != null' <<< "${projectSettings}" >/dev/null; then
            projectRuntime::_compose build web || return "${RC_ERROR}"
          fi ;;
        logs)
          if [[ -z "${parameter}" ]]; then projectRuntime::_compose logs -f
          else
            service="$(projectRuntime::_canonicalService "${parameter}")" || return "${RC_ERROR}"
            projectRuntime::_compose logs -f "${service}"
          fi ;;
        go)
          service="$(projectRuntime::_canonicalService "${parameter}")" || return "${RC_ERROR}"
          jq -e --arg service "${service}" '.services | index($service) != null' <<< "${projectSettings}" >/dev/null ||
            { message::error "Service '${service}' is not selected."; return "${RC_ERROR}"; }
          if [[ "${service}" == web ]]; then
            projectRuntime::_compose exec --user "${value:-magento}" "${service}" bash
          else projectRuntime::_compose exec --user "${value:-root}" "${service}" sh; fi ;;
      esac ;;
  esac
  status=$?
  projectRuntime::_cleanup
  projectLock=""
  trap - EXIT INT TERM HUP
  return "${status}"
)
