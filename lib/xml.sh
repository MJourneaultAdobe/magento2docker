#!/usr/bin/env bash
###########################################################
# XML / XPath helpers shared across libraries that drive
# xmlstarlet against m2d XML files.
###########################################################

source "$(dirname -- "${BASH_SOURCE[0]}")"/bootstrap.sh || return 255

# Prevent the library from being sourced more than once.
[[ -n "${_LIB_XML_SH:-}" ]] && return
readonly _LIB_XML_SH=1

source "${M2D_LIBRARIES_ROOT}"/message.sh

###########################################################
# Counts XML nodes matching an XPath expression in a file
# using xmlstarlet.
# Arguments:
#   file,  (string) Path to the XML file
#   xpath, (string) XPath expression to count
# Outputs:
#   Match count (integer) to stdout on success
# Returns:
#   RC_OK on success
#   RC_ERROR on lookup error or unexpected output
###########################################################
xml::count() {
  local -r file="${1:?file is not set}"
  local -r xpath="${2:?xpath is not set}"
  local output
  output=$(xmlstarlet sel -t -v "count(${xpath})" "${file}" 2>&1) || {
    message::error "Failed to count '${xpath}' in ${file}: ${output}"
    return "${RC_ERROR}"
  }
  [[ "${output}" =~ ^[0-9]+$ ]] || {
    message::error "Unexpected count output for '${xpath}' in ${file}: ${output}"
    return "${RC_ERROR}"
  }
  printf '%s\n' "${output}"
}

###########################################################
# Counts XML nodes matching one or more XPath expressions
# in a single xmlstarlet invocation. Emits one integer per
# expression, in the order supplied, separated by newlines.
# Arguments:
#   file,   (string)  Path to the XML file
#   xpaths, (varargs) One or more XPath expressions to
#                     count. At least one is required.
# Outputs:
#   One match count per expression to stdout
# Returns:
#   RC_OK on success
#   RC_ERROR on missing arguments, lookup error, or unexpected output
###########################################################
xml::countMany() {
  local -r file="${1:?file is not set}"

  shift
  (( $# > 0 )) || {
    message::error "xml::countMany: at least one xpath required."
    return "${RC_ERROR}"
  }

  local -a args=(-t)
  local xpath
  for xpath in "$@"; do
    args+=(-v "count(${xpath})" -n)
  done

  local output
  output=$(xmlstarlet sel "${args[@]}" "${file}" 2>&1) || {
    message::error "Failed to count xpaths in ${file}: ${output}"
    return "${RC_ERROR}"
  }

  local line
  while IFS= read -r line; do
    [[ "${line}" =~ ^[0-9]+$ ]] || {
      message::error "Unexpected count output in ${file}: ${output}"
      return "${RC_ERROR}"
    }
  done <<< "${output}"
  printf '%s\n' "${output}"
}

###########################################################
# Deletes one or more XML nodes (or attributes) matching
# the supplied XPath expressions from a file.
# Each XPath is passed to xmlstarlet as a separate `-d` operation.
# Arguments:
#   file,   (string)  Path to the XML file to modify
#   xpaths, (varargs) One or more XPath expressions to
#                     delete. At least one is required.
# Returns:
#   RC_OK on success
#   RC_ERROR on missing arguments or xmlstarlet failure
###########################################################
xml::delete() {
  local -r file="${1:?file is not set}"
  shift
  (( $# > 0 )) || {
    message::error "xml::delete: at least one xpath required"
    return "${RC_ERROR}"
  }
  local -a args=()
  local xpath
  for xpath in "$@"; do
    args+=(-d "${xpath}")
  done
  xml::edit "${file}" "${args[@]}"
}

###########################################################
# Performs an in-place xmlstarlet edit on a file.
# Arguments:
#   file,    (string)  Path to the XML file to modify
#   ed-args, (varargs) Arguments forwarded to `xmlstarlet ed --inplace`.
#                      At least one is required.
# Returns:
#   RC_OK on success
#   RC_ERROR on missing arguments or xmlstarlet failure
###########################################################
xml::edit() {
  local -r file="${1:?file is not set}"
  shift
  (( $# > 0 )) || {
    message::error "xml::edit: at least one ed-arg required"
    return "${RC_ERROR}"
  }
  local err
  err=$(xmlstarlet ed --inplace "$@" "${file}" 2>&1) || {
    message::error "Failed to edit XML file ${file}: ${err}"
    return "${RC_ERROR}"
  }
}

###########################################################
# Validates the library requirements are met.
# Outputs:
#   Writes error message to stderr
# Returns:
#   RC_OK Requirements met
#   RC_ERROR Requirements not met
###########################################################
xml::selfCheck() {
  command -v xmlstarlet &>/dev/null || {
    message::error "xmlstarlet is required but not installed. Install it with your package manager (e.g. brew install xmlstarlet)."
    return "${RC_ERROR}"
  }

  return "${RC_OK}"
}

###########################################################
# Reads the values of the XML nodes matching an XPath
# expression in a file using xmlstarlet.
# Arguments:
#   file,  (string) Path to the XML file
#   xpath, (string) XPath expression to read
# Outputs:
#   One value per matched node to stdout, nothing when the
#   expression matches no node
# Returns:
#   RC_OK on success
#   RC_ERROR on lookup error
###########################################################
xml::values() {
  local -r file="${1:?file is not set}"
  local -r xpath="${2:?xpath is not set}"
  local output rc=0
  output=$(xmlstarlet sel -T -t -m "${xpath}" -v "." -n "${file}" 2>&1) || rc=$?
  # xmlstarlet sel exits 1 without output when the expression matches no node.
  if (( rc == 1 )) && [[ -z "${output}" ]]; then
    rc=0
  fi
  (( rc == 0 )) || {
    message::error "Failed to read '${xpath}' in ${file}: ${output}"
    return "${RC_ERROR}"
  }
  printf '%s\n' "${output}"
}

###########################################################
# Renders an arbitrary string as a safe XPath 1.0 string
# literal. XPath 1.0 has no escape syntax for embedded
# quotes; values containing a single quote are wrapped in
# concat().
# Arguments:
#   value, (string) value to encode
# Outputs:
#   XPath-safe expression to stdout (e.g. 'foo' or
# concat('o', "'", 'brien'))
###########################################################
xml::xpathLiteral() {
  local -r value="${1?value is not set}"
  if [[ "${value}" != *\'* ]]; then
    printf "'%s'" "${value}"
    return "${RC_OK}"
  fi
  # Replace each ' with ', "'", ' so the result, wrapped in
  # concat('...'), produces a valid XPath expression.
  printf "concat('%s')" "${value//\'/\', \"\'\", \'}"
}
