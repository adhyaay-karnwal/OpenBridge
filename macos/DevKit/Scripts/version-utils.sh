#!/bin/bash
# version-utils.sh - Version parsing utilities (legacy compatibility)
# Prefer using project-env.sh for new scripts

sanitize_version() {
  echo "$1" | sed 's/[[:space:]]*\/\/.*//' | sed 's/[[:space:]]*\/\*.*//' | tr -d ' ' |
    grep -oE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?' || echo "1.0.0"
}

sanitize_build_number() {
  echo "$1" | sed 's/[[:space:]]*\/\/.*//' | sed 's/[[:space:]]*\/\*.*//' | tr -d ' ' |
    grep -oE '^[0-9]+' || echo "1"
}

read_marketing_version() {
  sanitize_version "$(grep 'MARKETING_VERSION' "$1" | sed 's/.*= *//')"
}

read_project_version() {
  sanitize_build_number "$(grep 'CURRENT_PROJECT_VERSION' "$1" | sed 's/.*= *//')"
}
