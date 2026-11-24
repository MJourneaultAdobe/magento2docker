#!/usr/bin/env bash
###########################################################
# Resolves the libraries root so libraries can locate their
# siblings. Sourced by every library, which makes each one
# usable on its own (unit tests) as well as through m2d.
###########################################################

# Require the bash features used by m2d before any library can source
# bash 4-only syntax.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
  printf "m2d requires Bash 4.3 or later; running Bash %s. Install Bash with Homebrew (brew install bash) and put its bin directory first in PATH.\n" "${BASH_VERSION}" 1>&2
  return 255 2>/dev/null || exit 255
fi

# Prevent the library from being sourced more than once.
[[ -n "${_LIB_BOOTSTRAP_SH:-}" ]] && return
readonly _LIB_BOOTSTRAP_SH=1

# M2D_LIBRARIES_ROOT is the directory holding this file.
# An inherited value is kept so callers may override the location.
if [[ -z "${M2D_LIBRARIES_ROOT:-}" ]]; then
  if command -v realpath &>/dev/null; then
    M2D_LIBRARIES_ROOT="$(CDPATH='' cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)"
  else
    # realpath is missing on macOS 12 and older without coreutils: follow the
    # file symlinks with readlink, then let pwd -P resolve the directories.
    _bootstrapPath="${BASH_SOURCE[0]}"
    while [[ -L "${_bootstrapPath}" ]]; do
      _bootstrapLink="$(readlink -- "${_bootstrapPath}")"
      [[ "${_bootstrapLink}" == /* ]] || _bootstrapLink="$(dirname -- "${_bootstrapPath}")/${_bootstrapLink}"
      _bootstrapPath="${_bootstrapLink}"
    done
    M2D_LIBRARIES_ROOT="$(CDPATH='' cd -- "$(dirname -- "${_bootstrapPath}")" && pwd -P)"
    unset _bootstrapPath _bootstrapLink
  fi
  readonly M2D_LIBRARIES_ROOT
fi

# Return codes shared by every library and by m2d.
#   RC_OK    Success, or a predicate answering "yes".
#   RC_NO    Expected negative outcome: predicate answering "no", entry
#            already exists, nothing to do. Never an error.
#   RC_ERROR Failure.
# shellcheck disable=SC2034
readonly RC_OK=0
# shellcheck disable=SC2034
readonly RC_NO=1
# shellcheck disable=SC2034
readonly RC_ERROR=255
