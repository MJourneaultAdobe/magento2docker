#!/usr/bin/env bash
###########################################################
# Adobe Commerce system requirements matrix, imported from
# the Experience League system requirements page source
# and stored in the app settings store
# <m2d>/.m2d/system-requirements.json:
#   { "<commerce version>": { "<service>": "<versions>" } }
# Cloud-only requirements use a "<service> Cloud" key.
###########################################################

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

# Prevent the library from being sourced more than once.
[[ -n "${_LIB_SYSTEM_REQUIREMENTS_SH:-}" ]] && return
readonly _LIB_SYSTEM_REQUIREMENTS_SH=1

source "${M2D_LIBRARIES_ROOT}"/message.sh
source "${M2D_LIBRARIES_ROOT}"/settingsManager.sh

readonly _SYSTEM_REQUIREMENTS_SOURCE_URL="https://raw.githubusercontent.com/AdobeDocs/commerce-operations.en/main/_jekyll/_data/system-requirements.yml"
readonly SYSTEM_REQUIREMENTS_STORE="system-requirements.json"

###########################################################
# Parses the system requirements YAML source. The source
# holds one mapping per Commerce version, each mapping a
# service to its supported versions.
# Arguments:
#   None, reads the YAML from stdin
# Outputs:
#   One "version<TAB>service<TAB>value" line per
#   requirement to stdout
# Returns:
#   RC_OK on success
#   RC_ERROR if the source holds no requirement
###########################################################
systemRequirements::_parse() {
  local line version="" service value count=0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    if [[ "${line}" =~ ^([^[:space:]#][^:]*):[[:space:]]*$ ]]; then
      version="${BASH_REMATCH[1]% (latest)}"
    elif [[ -n "${version}" && "${line}" =~ ^[[:space:]]+([^:#][^:]*):[[:space:]]+(.+)$ ]]; then
      service="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]%"${BASH_REMATCH[2]##*[![:space:]]}"}"
      if [[ "${value}" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]//\'\'/\'}"
      elif [[ "${value}" =~ ^\"(.*)\"$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi
      printf '%s\t%s\t%s\n' "${version}" "${service}" "${value}"
      (( ++count ))
    fi
  done

  (( count > 0 )) || {
    message::error "No system requirement found in the source."
    return "${RC_ERROR}"
  }
}

###########################################################
# Loads the supported versions of a service for a Commerce
# version.
# Arguments:
#   version, (string) Commerce version, e.g. 2.4.8-p3
#   service, (string) Service name, e.g. PHP, MySQL,
#            OpenSearch Cloud
# Outputs:
#   Supported versions to stdout, e.g. "8.4, 8.3"
# Returns:
#   RC_OK on success
#   RC_NO if the requirement does not exist
#   RC_ERROR in case of error
###########################################################
systemRequirements::get() {
  local -r version="${1:?version is not set}"
  local -r service="${2:?service is not set}"

  settingsManager::load "${SETTINGS_MANAGER_SCOPE_APP}" "${version}" "${service}" "${SYSTEM_REQUIREMENTS_STORE}"
}

###########################################################
# Checks that the tools required by the library are
# installed.
# Returns:
#   RC_OK if all tools are installed
#   RC_ERROR otherwise
###########################################################
systemRequirements::selfCheck() {
  local tool
  for tool in curl jq; do
    command -v "${tool}" &>/dev/null || {
      message::error "${tool} is required but not installed. Install it with your package manager (e.g. brew install ${tool})."
      return "${RC_ERROR}"
    }
  done

  return "${RC_OK}"
}

###########################################################
# Lists the services of a Commerce version.
# Arguments:
#   version, (string) Commerce version, e.g. 2.4.8-p3
# Outputs:
#   One service name per line to stdout
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
systemRequirements::services() {
  local -r version="${1:?version is not set}"

  settingsManager::keys "${SETTINGS_MANAGER_SCOPE_APP}" "${version}" "${SYSTEM_REQUIREMENTS_STORE}"
}

###########################################################
# Downloads the system requirements and replaces the
# stored matrix.
# Globals:
#   SYSTEM_REQUIREMENTS_STORE
# Arguments:
#   None
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
systemRequirements::update() {
  systemRequirements::selfCheck || return $?

  local source
  source="$(curl -fsSL "${_SYSTEM_REQUIREMENTS_SOURCE_URL}")" || {
    message::error "Failed to download the system requirements from ${_SYSTEM_REQUIREMENTS_SOURCE_URL}."
    return "${RC_ERROR}"
  }

  local requirements
  requirements="$(systemRequirements::_parse <<< "${source}")" || return $?

  local storeFile
  storeFile="$(settingsManager::file "${SETTINGS_MANAGER_SCOPE_APP}" "${SYSTEM_REQUIREMENTS_STORE}")" || return $?
  printf '{}\n' > "${storeFile}" || {
    message::error "Failed to reset ${storeFile}."
    return "${RC_ERROR}"
  }

  local version service value
  while IFS=$'\t' read -r version service value; do
    settingsManager::save "${SETTINGS_MANAGER_SCOPE_APP}" "${version}" "${service}" "${value}" "${SYSTEM_REQUIREMENTS_STORE}" || return $?
  done <<< "${requirements}"

  message::notice "System requirements saved to ${storeFile}."
}

###########################################################
# Lists the Commerce versions of the stored matrix.
# Outputs:
#   One Commerce version per line to stdout, newest first
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
systemRequirements::versions() {
  settingsManager::libraries "${SETTINGS_MANAGER_SCOPE_APP}" "${SYSTEM_REQUIREMENTS_STORE}"
}
