#!/usr/bin/env bash
###########################################################
# Loads and saves m2d settings in XML or JSON stores. Two
# scopes are available:
#   app   Application settings, stored in the m2d
#         installation directory: <m2d>/.m2d/<store>
#   user  User settings, stored in the user's home
#         directory: ~/.m2d/<store>
# The store is a file name ending in .xml or .json and
# defaults to settings.xml. Settings are grouped by the
# library owning them:
#   <settings>
#     <library name="dataSource">
#       <setting name="key">value</setting>
#     </library>
#   </settings>
#   { "dataSource": { "key": "value" } }
###########################################################

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

# Prevent the library from being sourced more than once.
[[ -n "${_LIB_SETTINGS_MANAGER_SH:-}" ]] && return
readonly _LIB_SETTINGS_MANAGER_SH=1

source "${M2D_LIBRARIES_ROOT}"/xml.sh
source "${M2D_LIBRARIES_ROOT}"/message.sh

readonly _SETTINGS_MANAGER_DIRECTORY=".m2d"
readonly _SETTINGS_MANAGER_ROOT_XPATH="/settings"
readonly _SETTINGS_MANAGER_TYPE_JSON="json"
readonly _SETTINGS_MANAGER_TYPE_XML="xml"
# shellcheck disable=SC2034
readonly SETTINGS_MANAGER_DEFAULT_STORE="settings.xml"
# shellcheck disable=SC2034
readonly SETTINGS_MANAGER_SCOPE_APP="app"
# shellcheck disable=SC2034
readonly SETTINGS_MANAGER_SCOPE_USER="user"

###########################################################
# Creates a settings file when missing.
# Arguments:
#   file, (string) Path to the settings file
# Returns:
#   RC_OK if the settings file exists
#   RC_ERROR in case of error
###########################################################
settingsManager::_createFile() {
  local -r file="${1:?file is not set}"

  if [[ -f "${file}" ]]; then
    return "${RC_OK}"
  fi

  local type
  type="$(settingsManager::_storeType "$(basename -- "${file}")")" || return $?

  mkdir -p "$(dirname -- "${file}")" || {
    message::error "Failed to create directory for ${file}."
    return "${RC_ERROR}"
  }

  local content
  if [[ "${type}" == "${_SETTINGS_MANAGER_TYPE_JSON}" ]]; then
    content='{}'
  else
    content='<?xml version="1.0" encoding="UTF-8"?>
<settings>
</settings>'
  fi
  printf '%s\n' "${content}" > "${file}" || {
    message::error "Failed to write ${file}."
    return "${RC_ERROR}"
  }
}

###########################################################
# Resolves the path of a scope's settings file, without
# creating it.
# Globals:
#   HOME
#   M2D_LIBRARIES_ROOT
# Arguments:
#   scope, (string) Settings scope: app or user
#   store, (string) Store file name, optional
# Outputs:
#   Settings file path to stdout
# Returns:
#   RC_OK on success
#   RC_ERROR if the scope or store is invalid
###########################################################
settingsManager::_filePath() {
  local -r scope="${1:?scope is not set}"
  local -r store="${2:-${SETTINGS_MANAGER_DEFAULT_STORE}}"

  settingsManager::_storeType "${store}" > /dev/null || return $?

  case "${scope}" in
    "${SETTINGS_MANAGER_SCOPE_APP}")
      printf '%s\n' "$(dirname -- "${M2D_LIBRARIES_ROOT}")/${_SETTINGS_MANAGER_DIRECTORY}/${store}"
      ;;
    "${SETTINGS_MANAGER_SCOPE_USER}")
      [[ -n "${HOME:-}" ]] || {
        message::error "HOME is not set; cannot resolve the user settings file."
        return "${RC_ERROR}"
      }
      printf '%s\n' "${HOME}/${_SETTINGS_MANAGER_DIRECTORY}/${store}"
      ;;
    *)
      message::error "Invalid settings scope '${scope}'. Expected '${SETTINGS_MANAGER_SCOPE_APP}' or '${SETTINGS_MANAGER_SCOPE_USER}'."
      return "${RC_ERROR}"
      ;;
  esac
}

###########################################################
# Applies a jq filter to a JSON settings file in place.
# Arguments:
#   file,   (string) Path to the settings file
#   filter, (string) jq filter
#   ...,    jq options, e.g. --arg name value
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
settingsManager::_jsonEdit() {
  local -r file="${1:?file is not set}"
  local -r filter="${2:?filter is not set}"
  shift 2

  local tmpFile output
  tmpFile="$(mktemp "${file}.XXXXXX")" || {
    message::error "Failed to create a temporary file for ${file}."
    return "${RC_ERROR}"
  }
  if ! output=$(jq "$@" "${filter}" "${file}" 2>&1 > "${tmpFile}"); then
    rm -f -- "${tmpFile}"
    message::error "Failed to edit ${file}: ${output}"
    return "${RC_ERROR}"
  fi
  # Copying the content keeps the settings file permissions.
  cat -- "${tmpFile}" > "${file}" || {
    rm -f -- "${tmpFile}"
    message::error "Failed to write ${file}."
    return "${RC_ERROR}"
  }
  rm -f -- "${tmpFile}"
}

###########################################################
# Builds the XPath of a library element.
# Arguments:
#   library, (string) Library name
# Outputs:
#   XPath to stdout
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
settingsManager::_libraryXpath() {
  local -r library="${1:?library is not set}"

  local libraryPred
  libraryPred="$(xml::xpathLiteral "${library}")" || return "${RC_ERROR}"

  printf '%s\n' "${_SETTINGS_MANAGER_ROOT_XPATH}/library[@name=${libraryPred}]"
}

###########################################################
# Builds the XPath of a setting element.
# Arguments:
#   library, (string) Library name
#   key,     (string) Setting name
# Outputs:
#   XPath to stdout
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
settingsManager::_settingXpath() {
  local -r library="${1:?library is not set}"
  local -r key="${2:?key is not set}"

  local libraryXpath keyPred
  libraryXpath="$(settingsManager::_libraryXpath "${library}")" || return "${RC_ERROR}"
  keyPred="$(xml::xpathLiteral "${key}")" || return "${RC_ERROR}"

  printf '%s\n' "${libraryXpath}/setting[@name=${keyPred}]"
}

###########################################################
# Validates a store file name and prints its type.
# Arguments:
#   store, (string) Store file name
# Outputs:
#   Store type to stdout: json or xml
# Returns:
#   RC_OK on success
#   RC_ERROR if the store name is invalid
###########################################################
settingsManager::_storeType() {
  local -r store="${1:?store is not set}"

  if [[ "${store}" == */* || "${store}" == .* ]]; then
    message::error "Invalid settings store '${store}'. Expected a file name."
    return "${RC_ERROR}"
  fi
  case "${store}" in
    *.json) printf '%s\n' "${_SETTINGS_MANAGER_TYPE_JSON}" ;;
    *.xml) printf '%s\n' "${_SETTINGS_MANAGER_TYPE_XML}" ;;
    *)
      message::error "Invalid settings store '${store}'. Expected a .json or .xml file."
      return "${RC_ERROR}"
      ;;
  esac
}

###########################################################
# Checks whether a scope's settings file exists, without
# creating it.
# Arguments:
#   scope, (string) Settings scope: app or user
#   store, (string) Store file name, optional
# Returns:
#   RC_OK if the settings file exists
#   RC_NO otherwise
#   RC_ERROR in case of error
###########################################################
settingsManager::exists() {
  local -r scope="${1:?scope is not set}"
  local -r store="${2:-}"

  local settingsFile
  settingsFile="$(settingsManager::_filePath "${scope}" "${store}")" || return $?
  [[ -f "${settingsFile}" ]] || return "${RC_NO}"
}

###########################################################
# Prints the absolute path to a scope's settings file,
# creating the file when missing.
# Arguments:
#   scope, (string) Settings scope: app or user
#   store, (string) Store file name, optional
# Outputs:
#   Settings file path to stdout
# Returns:
#   RC_OK if path resolved
#   RC_ERROR in case of error
###########################################################
settingsManager::file() {
  local -r scope="${1:?scope is not set}"
  local -r store="${2:-}"

  local settingsFile
  settingsFile="$(settingsManager::_filePath "${scope}" "${store}")" || return $?
  settingsManager::_createFile "${settingsFile}" || return $?
  printf '%s\n' "${settingsFile}"
}

###########################################################
# Lists the settings of a library. A missing settings file
# is not created.
# Arguments:
#   scope,   (string) Settings scope: app or user
#   library, (string) Library name
#   store,   (string) Store file name, optional
# Outputs:
#   One setting name per line to stdout, in storage order,
#   nothing when the library holds no settings
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
settingsManager::keys() {
  local -r scope="${1:?scope is not set}"
  local -r library="${2:?library is not set}"
  local -r store="${3:-${SETTINGS_MANAGER_DEFAULT_STORE}}"

  local settingsFile type
  settingsFile="$(settingsManager::_filePath "${scope}" "${store}")" || return $?
  type="$(settingsManager::_storeType "${store}")" || return $?
  [[ -f "${settingsFile}" ]] || return "${RC_OK}"

  local output rc=0
  if [[ "${type}" == "${_SETTINGS_MANAGER_TYPE_JSON}" ]]; then
    output=$(jq -r --arg library "${library}" \
      '.[$library] // {} | keys_unsorted[]' "${settingsFile}" 2>&1) || rc=$?
  else
    local libraryXpath
    libraryXpath="$(settingsManager::_libraryXpath "${library}")" || return $?
    # Text mode (-T) outputs the names unescaped.
    output=$(xmlstarlet sel -T -t -m "${libraryXpath}/setting" -v "@name" -n "${settingsFile}" 2>&1) || rc=$?
    # xmlstarlet sel exits 1 without output when the expression matches no node.
    if (( rc == 1 )) && [[ -z "${output}" ]]; then
      return "${RC_OK}"
    fi
  fi
  (( rc == 0 )) || {
    message::error "Failed to list settings of library '${library}' from ${settingsFile}: ${output}"
    return "${RC_ERROR}"
  }
  [[ -z "${output}" ]] || printf '%s\n' "${output}"
}

###########################################################
# Lists the libraries holding settings. A missing settings
# file is not created.
# Arguments:
#   scope, (string) Settings scope: app or user
#   store, (string) Store file name, optional
# Outputs:
#   One library name per line to stdout, in storage order
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
settingsManager::libraries() {
  local -r scope="${1:?scope is not set}"
  local -r store="${2:-${SETTINGS_MANAGER_DEFAULT_STORE}}"

  local settingsFile type
  settingsFile="$(settingsManager::_filePath "${scope}" "${store}")" || return $?
  type="$(settingsManager::_storeType "${store}")" || return $?
  [[ -f "${settingsFile}" ]] || return "${RC_OK}"

  local output rc=0
  if [[ "${type}" == "${_SETTINGS_MANAGER_TYPE_JSON}" ]]; then
    output=$(jq -r 'keys_unsorted[]' "${settingsFile}" 2>&1) || rc=$?
  else
    output=$(xmlstarlet sel -T -t -m "${_SETTINGS_MANAGER_ROOT_XPATH}/library" -v "@name" -n "${settingsFile}" 2>&1) || rc=$?
    # xmlstarlet sel exits 1 without output when the expression matches no node.
    if (( rc == 1 )) && [[ -z "${output}" ]]; then
      return "${RC_OK}"
    fi
  fi
  (( rc == 0 )) || {
    message::error "Failed to list libraries from ${settingsFile}: ${output}"
    return "${RC_ERROR}"
  }
  [[ -z "${output}" ]] || printf '%s\n' "${output}"
}

###########################################################
# Loads a setting value. A missing settings file is not
# created.
# Arguments:
#   scope,   (string) Settings scope: app or user
#   library, (string) Library owning the setting
#   key,     (string) Setting name
#   store,   (string) Store file name, optional
# Outputs:
#   Setting value to stdout
# Returns:
#   RC_OK on success
#   RC_NO if the setting does not exist
#   RC_ERROR in case of error
###########################################################
settingsManager::load() {
  local -r scope="${1:?scope is not set}"
  local -r library="${2:?library is not set}"
  local -r key="${3:?key is not set}"
  local -r store="${4:-${SETTINGS_MANAGER_DEFAULT_STORE}}"

  local settingsFile type
  settingsFile="$(settingsManager::_filePath "${scope}" "${store}")" || return $?
  type="$(settingsManager::_storeType "${store}")" || return $?
  [[ -f "${settingsFile}" ]] || return "${RC_NO}"

  local output rc=0
  if [[ "${type}" == "${_SETTINGS_MANAGER_TYPE_JSON}" ]]; then
    # Exit status 1 (-e) means the setting is missing.
    output=$(jq -e -j --arg library "${library}" --arg key "${key}" \
      '.[$library] // {} | if has($key) then .[$key] | tostring else null end' \
      "${settingsFile}" 2>&1) || rc=$?
    (( rc == 1 )) && return "${RC_NO}"
  else
    local settingXpath count
    settingXpath="$(settingsManager::_settingXpath "${library}" "${key}")" || return $?
    count=$(xml::count "${settingsFile}" "${settingXpath}") || return $?
    (( count > 0 )) || return "${RC_NO}"

    # Text mode (-T) outputs the value unescaped.
    output=$(xmlstarlet sel -T -t -v "${settingXpath}[1]" "${settingsFile}" 2>&1) || rc=$?
    # xmlstarlet sel exits 1 without output when the value is empty.
    if (( rc == 1 )) && [[ -z "${output}" ]]; then
      rc=0
    fi
  fi
  (( rc == 0 )) || {
    message::error "Failed to load setting '${key}' of library '${library}' from ${settingsFile}: ${output}"
    return "${RC_ERROR}"
  }
  printf '%s\n' "${output}"
}

###########################################################
# Removes a setting. The library is removed once it holds
# no more settings. A missing settings file is not created.
# Arguments:
#   scope,   (string) Settings scope: app or user
#   library, (string) Library owning the setting
#   key,     (string) Setting name
#   store,   (string) Store file name, optional
# Returns:
#   RC_OK on success
#   RC_NO if the setting does not exist
#   RC_ERROR in case of error
###########################################################
settingsManager::remove() {
  local -r scope="${1:?scope is not set}"
  local -r library="${2:?library is not set}"
  local -r key="${3:?key is not set}"
  local -r store="${4:-${SETTINGS_MANAGER_DEFAULT_STORE}}"

  local settingsFile type
  settingsFile="$(settingsManager::_filePath "${scope}" "${store}")" || return $?
  type="$(settingsManager::_storeType "${store}")" || return $?
  [[ -f "${settingsFile}" ]] || return "${RC_NO}"

  if [[ "${type}" == "${_SETTINGS_MANAGER_TYPE_JSON}" ]]; then
    local rc=0
    jq -e --arg library "${library}" --arg key "${key}" \
      '.[$library] // {} | has($key)' "${settingsFile}" > /dev/null 2>&1 || rc=$?
    (( rc == 0 )) || return "${RC_NO}"

    settingsManager::_jsonEdit "${settingsFile}" \
      'del(.[$library][$key]) | if .[$library] == {} then del(.[$library]) else . end' \
      --arg library "${library}" --arg key "${key}"
    return $?
  fi

  local libraryXpath settingXpath count
  libraryXpath="$(settingsManager::_libraryXpath "${library}")" || return $?
  settingXpath="$(settingsManager::_settingXpath "${library}" "${key}")" || return $?

  count=$(xml::count "${settingsFile}" "${settingXpath}") || return $?
  (( count > 0 )) || return "${RC_NO}"

  xml::delete "${settingsFile}" \
    "${settingXpath}" \
    "${libraryXpath}[not(setting)]"
}

###########################################################
# Saves a setting value, creating the settings file, the
# setting and its library when missing.
# Arguments:
#   scope,   (string) Settings scope: app or user
#   library, (string) Library owning the setting
#   key,     (string) Setting name
#   value,   (string) Setting value, may be empty
#   store,   (string) Store file name, optional
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
settingsManager::save() {
  local -r scope="${1:?scope is not set}"
  local -r library="${2:?library is not set}"
  local -r key="${3:?key is not set}"
  local -r value="${4?value is not set}"
  local -r store="${5:-${SETTINGS_MANAGER_DEFAULT_STORE}}"

  local settingsFile type
  settingsFile="$(settingsManager::_filePath "${scope}" "${store}")" || return $?
  type="$(settingsManager::_storeType "${store}")" || return $?
  settingsManager::_createFile "${settingsFile}" || return $?

  if [[ "${type}" == "${_SETTINGS_MANAGER_TYPE_JSON}" ]]; then
    settingsManager::_jsonEdit "${settingsFile}" '.[$library][$key] = $value' \
      --arg library "${library}" --arg key "${key}" --arg value "${value}"
    return $?
  fi

  local libraryXpath settingXpath
  libraryXpath="$(settingsManager::_libraryXpath "${library}")" || return $?
  settingXpath="$(settingsManager::_settingXpath "${library}" "${key}")" || return $?

  local libraryCount settingCount
  { read -r libraryCount; read -r settingCount; } < <(
    xml::countMany "${settingsFile}" "${libraryXpath}" "${settingXpath}"
  )
  [[ -n "${libraryCount}" && -n "${settingCount}" ]] || return "${RC_ERROR}"

  if (( settingCount > 0 )); then
    xml::edit "${settingsFile}" -u "${settingXpath}" -v "${value}"
    return $?
  fi

  local -a editArgs=()
  if (( libraryCount == 0 )); then
    editArgs+=(
      -s "${_SETTINGS_MANAGER_ROOT_XPATH}" -t elem -n library
      -i "${_SETTINGS_MANAGER_ROOT_XPATH}/library[last()]" -t attr -n name -v "${library}"
    )
  fi
  # The value is set by update: xmlstarlet drops values holding '&' on insert.
  editArgs+=(
    -s "${libraryXpath}" -t elem -n setting -v ""
    -i "${libraryXpath}/setting[last()]" -t attr -n name -v "${key}"
    -u "${settingXpath}" -v "${value}"
  )

  xml::edit "${settingsFile}" "${editArgs[@]}"
}
