#!/usr/bin/env bash
###########################################################
# Message helpers: colored notice, warning and error
# messages, and debug messages enabled by M2D_DEBUG.
###########################################################

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

# Prevent the library from being sourced more than once.
[[ -n "${_LIB_MESSAGE_SH:-}" ]] && return
readonly _LIB_MESSAGE_SH=1

# Terminal color settings
readonly _MESSAGE_COLOR_GREEN='\033[0;0;32m'
readonly _MESSAGE_COLOR_BOLDYELLOW='\033[0;1;33m'
readonly _MESSAGE_COLOR_BOLDRED='\033[0;1;31m'
readonly _MESSAGE_NO_COLOR='\033[0m'

###########################################################
# Checks whether colors may be emitted on the given stream.
# Globals:
#   NO_COLOR
# Arguments:
#   (int) File descriptor to check
# Returns:
#   RC_OK Colors may be emitted
#   RC_NO The stream is not a terminal or NO_COLOR is set
###########################################################
message::_colorEnabled() {
  local fileDescriptor="${1}"

  [[ -t "${fileDescriptor}" && -z "${NO_COLOR:-}" ]]
}

###########################################################
# Checks whether debug messages should be printed.
# Globals:
#   M2D_DEBUG
# Returns:
#   RC_OK Debug is enabled
#   RC_NO Debug is disabled
###########################################################
message::_debugEnabled() {
  local -r debugFlag="${M2D_DEBUG:-}"

  [[ "${debugFlag,,}" =~ ^(1|true|yes|on)$ ]]
}

###########################################################
# Prints a colored message when the output stream supports it.
# Arguments:
#   (int) File descriptor to write to
#   (string) ANSI color code
#   (mixed) Message to print
# Outputs:
#   Writes message to the given file descriptor
###########################################################
message::_print() {
  local fileDescriptor="${1}"
  local color="${2}"
  local message="${3}"
  local reset=""

  if ! message::_colorEnabled "${fileDescriptor}"; then
    color=""
  else
    reset="${_MESSAGE_NO_COLOR}"
  fi

  printf "%b%s%b\n" "${color}" "${message}" "${reset}" >&"${fileDescriptor}"
}

###########################################################
# Prints debug message with function name and line number.
# Arguments:
#   (mixed) Debug message to print
# Outputs:
#   Writes debug message to stderr when M2D_DEBUG is enabled
###########################################################
message::debug() {
  message::_debugEnabled || return "${RC_OK}"

  echo -n "debug: ${FUNCNAME[1]}() line ${BASH_LINENO[0]}: " 1>&2
  printf "%s\n" "${1}" 1>&2
}

###########################################################
# Prints error message.
# Arguments:
#   (mixed) Error message to print
# Outputs:
#   Writes error message to stderr
###########################################################
message::error() {
  if message::_debugEnabled; then
    echo -n "${FUNCNAME[1]}() line ${BASH_LINENO[0]}: " 1>&2
  fi
  message::_print 2 "${_MESSAGE_COLOR_BOLDRED}" "${1}"
}

###########################################################
# Prints notice message.
# Arguments:
#   (mixed) Notice message to print
# Outputs:
#   Writes notice message to stderr
###########################################################
message::notice() {
  message::_print 2 "${_MESSAGE_COLOR_GREEN}" "${1}"
}

###########################################################
# Prints warning message.
# Arguments:
#   (mixed) Warning message to print
# Outputs:
#   Writes warning message to stderr
###########################################################
message::warning() {
  message::_print 2 "${_MESSAGE_COLOR_BOLDYELLOW}" "${1}"
}
