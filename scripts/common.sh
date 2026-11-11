#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Shared installer functions

print() { printf '  %-7s %s\n' "$1" "$2"; }
die() { echo "Error: $*" >&2; exit 1; }

parse_options() {
  PLATFORM=
  COMPONENT=
  if [ "$#" -eq 1 ] && [ "$1" = --help ]; then
    usage
    exit 0
  fi
  while getopts ':p:c:h' option; do
    case "$option" in
      p)
        [ -z "$PLATFORM" ] || die "Specify -p only once"
        case "$OPTARG" in
          pi4|pi5) PLATFORM=$OPTARG ;;
          *) die "Invalid -p: $OPTARG (pi4|pi5)" ;;
        esac
        ;;
      c)
        [ -z "$COMPONENT" ] || die "Specify -c only once"
        case "$OPTARG" in
          all|service) COMPONENT=$OPTARG ;;
          *) die "Invalid -c: $OPTARG (all|service)" ;;
        esac
        ;;
      h) usage; exit 0 ;;
      :) die "Missing value for -$OPTARG" ;;
      \?) die "Unknown option: -$OPTARG" ;;
    esac
  done
  shift "$((OPTIND - 1))"
  [ "$#" -eq 0 ] || die "Unexpected argument: $1"
  [ -n "$PLATFORM" ] || die "Missing -p (pi4|pi5)"
  COMPONENT=${COMPONENT:-driver}
}

read_package_name() {
  PACKAGE_NAME=$(grep '^PACKAGE_NAME=' "$PROJECT_DIR/dkms.conf" | cut -d'"' -f2)
  : "${PACKAGE_NAME:?Missing PACKAGE_NAME}"
}

find_versions() {
  STATUS=$(dkms status -m "$PACKAGE_NAME")
  VERSIONS=$(printf '%s\n' "$STATUS" |
    awk -F '[/,:]' -v package="$PACKAGE_NAME" '$1 == package {print $2}' | sort -u)
}
