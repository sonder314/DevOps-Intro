#!/usr/bin/env bash

lab12_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LAB12_TOOL_ROOT="${lab12_repo_root}/.goenv/lab12"
export XDG_CACHE_HOME="${LAB12_TOOL_ROOT}/xdg-cache"
export XDG_CONFIG_HOME="${LAB12_TOOL_ROOT}/xdg-config"
export XDG_DATA_HOME="${LAB12_TOOL_ROOT}/xdg-data"
export TMPDIR="${LAB12_TOOL_ROOT}/tmp"
export GOCACHE="${LAB12_TOOL_ROOT}/go-build-cache"
export GOMODCACHE="${LAB12_TOOL_ROOT}/go-module-cache"
export PATH="${LAB12_TOOL_ROOT}/bin:${LAB12_TOOL_ROOT}/tinygo/bin:${lab12_repo_root}/.goenv/toolchain/bin:${PATH}"
mkdir -p \
  "${XDG_CACHE_HOME}" \
  "${XDG_CONFIG_HOME}" \
  "${XDG_DATA_HOME}" \
  "${TMPDIR}" \
  "${GOCACHE}" \
  "${GOMODCACHE}"
unset lab12_repo_root
