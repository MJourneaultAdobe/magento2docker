#!/usr/bin/env bash
###########################################################
# Loads and saves m2d settings in XML files. Two scopes
# are available:
#   app   Application settings, stored in the m2d
#         installation directory: <m2d>/.m2d/settings.xml
#   user  User settings, stored in the user's home
#         directory: ~/.m2d/settings.xml
# Settings are grouped by the library owning them:
#   <settings>
#     <library name="dataSource">
#       <setting name="key">value</setting>
#     </library>
#   </settings>
###########################################################

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

# Prevent the library from being sourced more than once.
[[ -n "${_LIB_SETTINGS_MANAGER_SH:-}" ]] && return
readonly _LIB_SETTINGS_MANAGER_SH=1

source "${M2D_LIBRARIES_ROOT}"/xml.sh
source "${M2D_LIBRARIES_ROOT}"/message.sh

readonly _SETTINGS_MANAGER_RELATIVE_PATH=".m2d/settings.xml"
readonly _SETTINGS_MANAGER_ROOT_XPATH="/settings"
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

  mkdir -p "$(dirname -- "${file}")" || {
    message::error "Failed to create directory for ${file}."
    return "${RC_ERROR}"
  }
  if ! cat > "${file}" << EOM
<?xml version="1.0" encoding="UTF-8"?>
<settings>
</settings>
EOM
  then
    message::error "Failed to write ${file}."
    return "${RC_ERROR}"
  fi
}

###########################################################
# Resolves the path of a scope's settings file, without
# creating it.
# Globals:
#   HOME
#   M2D_LIBRARIES_ROOT
# Arguments:
#   scope, (string) Settings scope: app or user
# Outputs:
#   Settings file path to stdout
# Returns:
#   RC_OK on success
#   RC_ERROR if the scope is invalid or cannot be resolved
###########################################################
settingsManager::_filePath() {
  local -r scope="${1:?scope is not set}"

  case "${scope}" in
    "${SETTINGS_MANAGER_SCOPE_APP}")
      printf '%s\n' "$(dirname -- "${M2D_LIBRARIES_ROOT}")/${_SETTINGS_MANAGER_RELATIVE_PATH}"
      ;;
    "${SETTINGS_MANAGER_SCOPE_USER}")
      [[ -n "${HOME:-}" ]] || {
        message::error "HOME is not set; cannot resolve the user settings file."
        return "${RC_ERROR}"
      }
      printf '%s\n' "${HOME}/${_SETTINGS_MANAGER_RELATIVE_PATH}"
      ;;
    *)
      message::error "Invalid settings scope '${scope}'. Expected '${SETTINGS_MANAGER_SCOPE_APP}' or '${SETTINGS_MANAGER_SCOPE_USER}'."
      return "${RC_ERROR}"
      ;;
  esac
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
# Checks whether a scope's settings file exists, without
# creating it.
# Arguments:
#   scope, (string) Settings scope: app or user
# Returns:
#   RC_OK if the settings file exists
#   RC_NO otherwise
#   RC_ERROR in case of error
###########################################################
settingsManager::exists() {
  local -r scope="${1:?scope is not set}"

  local settingsFile
  settingsFile="$(settingsManager::_filePath "${scope}")" || return $?
  [[ -f "${settingsFile}" ]] || return "${RC_NO}"
}

###########################################################
# Prints the absolute path to a scope's settings file,
# creating the file when missing.
# Arguments:
#   scope, (string) Settings scope: app or user
# Outputs:
#   Settings file path to stdout
# Returns:
#   RC_OK if path resolved
#   RC_ERROR in case of error
###########################################################
settingsManager::file() {
  local -r scope="${1:?scope is not set}"

  local settingsFile
  settingsFile="$(settingsManager::_filePath "${scope}")" || return $?
  settingsManager::_createFile "${settingsFile}" || return $?
  printf '%s\n' "${settingsFile}"
}

###########################################################
# Lists the settings of a library. A missing settings file
# is not created.
# Arguments:
#   scope,   (string) Settings scope: app or user
#   library, (string) Library name
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

  local settingsFile
  settingsFile="$(settingsManager::_filePath "${scope}")" || return $?
  [[ -f "${settingsFile}" ]] || return "${RC_OK}"

  local libraryXpath
  libraryXpath="$(settingsManager::_libraryXpath "${library}")" || return $?

  # Text mode (-T) outputs the names unescaped.
  local output rc=0
  output=$(xmlstarlet sel -T -t -m "${libraryXpath}/setting" -v "@name" -n "${settingsFile}" 2>&1) || rc=$?
  # xmlstarlet sel exits 1 without output when the expression matches no node.
  if (( rc == 1 )) && [[ -z "${output}" ]]; then
    return "${RC_OK}"
  fi
  (( rc == 0 )) || {
    message::error "Failed to list settings of library '${library}' from ${settingsFile}: ${output}"
    return "${RC_ERROR}"
  }
  printf '%s\n' "${output}"
}

###########################################################
# Loads a setting value. A missing settings file is not
# created.
# Arguments:
#   scope,   (string) Settings scope: app or user
#   library, (string) Library owning the setting
#   key,     (string) Setting name
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

  local settingsFile
  settingsFile="$(settingsManager::_filePath "${scope}")" || return $?
  [[ -f "${settingsFile}" ]] || return "${RC_NO}"

  local settingXpath count
  settingXpath="$(settingsManager::_settingXpath "${library}" "${key}")" || return $?

  count=$(xml::count "${settingsFile}" "${settingXpath}") || return $?
  (( count > 0 )) || return "${RC_NO}"

  # Text mode (-T) outputs the value unescaped.
  local output rc=0
  output=$(xmlstarlet sel -T -t -v "${settingXpath}[1]" "${settingsFile}" 2>&1) || rc=$?
  # xmlstarlet sel exits 1 without output when the value is empty.
  if (( rc == 1 )) && [[ -z "${output}" ]]; then
    rc=0
  fi
  (( rc == 0 )) || {
    message::error "Failed to load setting '${key}' of library '${library}' from ${settingsFile}: ${output}"
    return "${RC_ERROR}"
  }
  printf '%s\n' "${output}"
}

###########################################################
# Removes a setting. The library element is removed once it
# holds no more settings. A missing settings file is not
# created.
# Arguments:
#   scope,   (string) Settings scope: app or user
#   library, (string) Library owning the setting
#   key,     (string) Setting name
# Returns:
#   RC_OK on success
#   RC_NO if the setting does not exist
#   RC_ERROR in case of error
###########################################################
settingsManager::remove() {
  local -r scope="${1:?scope is not set}"
  local -r library="${2:?library is not set}"
  local -r key="${3:?key is not set}"

  local settingsFile
  settingsFile="$(settingsManager::_filePath "${scope}")" || return $?
  [[ -f "${settingsFile}" ]] || return "${RC_NO}"

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
# setting and its library element when missing.
# Arguments:
#   scope,   (string) Settings scope: app or user
#   library, (string) Library owning the setting
#   key,     (string) Setting name
#   value,   (string) Setting value, may be empty
# Returns:
#   RC_OK on success
#   RC_ERROR in case of error
###########################################################
settingsManager::save() {
  local -r scope="${1:?scope is not set}"
  local -r library="${2:?library is not set}"
  local -r key="${3:?key is not set}"
  local -r value="${4?value is not set}"

  local settingsFile
  settingsFile="$(settingsManager::_filePath "${scope}")" || return $?
  settingsManager::_createFile "${settingsFile}" || return $?

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
