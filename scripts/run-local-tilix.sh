#!/usr/bin/env bash
set -euo pipefail

script_path=$(readlink -f -- "${BASH_SOURCE[0]}")
script_dir=$(dirname -- "$script_path")
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)

usage() {
    cat <<'EOF'
Usage: scripts/run-local-tilix.sh [--mode baseline|optimized] [Tilix options...]

Modes:
  baseline   Modern rendering with transparency enabled (background CSS retained)
  optimized  Modern rendering with transparency disabled (background CSS skipped)
  (omitting --mode uses your current Tilix settings)

Example:
  scripts/run-local-tilix.sh --mode optimized --maximize \
    --command='loom-repaint-probe --fps 120'

The default profile is made to inherit the global modern rendering path for the run.
Mode settings and the profile override are restored when the launched process exits.
EOF
}

mode=default
case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
    --mode)
        if test "$#" -lt 2
        then
            printf 'ERROR: --mode requires baseline or optimized.\n' >&2
            exit 2
        fi
        mode=$2
        shift 2
        ;;
    --mode=*)
        mode=${1#*=}
        shift
        ;;
esac

if test "$mode" != default && test "$mode" != baseline && test "$mode" != optimized
then
    printf 'ERROR: unknown mode %s; use baseline or optimized.\n' "$mode" >&2
    exit 2
fi

if test ! -x "$repo_root/tilix"
then
    printf 'ERROR: %s is missing; run make build first.\n' "$repo_root/tilix" >&2
    exit 1
fi

runtime_dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
schema_dir=$(mktemp -d "$runtime_dir/tilix-gsettings.XXXXXXXX")
previous_rendering_path=
previous_transparency=
profile_settings=
previous_profile_rendering_path=
restore_settings=0
cleanup() {
    if test "$restore_settings" -eq 1
    then
        GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings set "$profile_settings" rendering-path "$previous_profile_rendering_path"
        GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings set com.gexperts.Tilix.Settings rendering-path "$previous_rendering_path"
        GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings set com.gexperts.Tilix.Settings enable-transparency "$previous_transparency"
    fi
    rm -rf -- "$schema_dir"
}
trap cleanup EXIT

glib-compile-schemas --strict --targetdir="$schema_dir" "$repo_root/data/gsettings"

# Preserve the user's normal GSettings backend and values. The local schema
# directory avoids errors from an older system-installed Tilix schema.
if test "$mode" != default
then
    previous_rendering_path=$(GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings get com.gexperts.Tilix.Settings rendering-path)
    previous_transparency=$(GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings get com.gexperts.Tilix.Settings enable-transparency)
    profile_id=$(GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings get com.gexperts.Tilix.ProfilesList default)
    profile_id=${profile_id#\'}
    profile_id=${profile_id%\'}
    profile_settings="com.gexperts.Tilix.Profile:/com/gexperts/Tilix/profiles/$profile_id/"
    previous_profile_rendering_path=$(GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings get "$profile_settings" rendering-path)
    restore_settings=1
    GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings set "$profile_settings" rendering-path 'default'
    GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings set com.gexperts.Tilix.Settings rendering-path 'modern'
    if test "$mode" = baseline
    then
        GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings set com.gexperts.Tilix.Settings enable-transparency true
    else
        GSETTINGS_SCHEMA_DIR="$schema_dir" gsettings set com.gexperts.Tilix.Settings enable-transparency false
    fi
fi

if test "$mode" = default
then
    printf 'Running with your current Tilix settings.\n'
else
    transparency_state=disabled
    if test "$mode" = baseline
    then
        transparency_state=enabled
    fi
    printf 'Running %s mode (modern rendering, transparency %s). Settings will be restored on exit.\n' \
        "$mode" "$transparency_state"
fi

GSETTINGS_SCHEMA_DIR="$schema_dir" "$repo_root/tilix" --new-process "$@"
