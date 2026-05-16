#!/usr/bin/env bash
COMMON_PATHS=(
    "/usr/local/bin"
    "/usr/bin"
    "$HOME/.local/bin"
)

CONFIGURATION_PATHS=(
    "/etc"
    "/var/lib"
    "$HOME/.config"
    "$HOME/.local/share"
    "$HOME"
)

TMP_CONFIG_DIR=""
TMP_CONFIG_FILE=""

#if _is_root; then
#    CONFIGURATION_PATHS=(/etc /var/lib)
#else
#    CONFIGURATION_PATHS=("$HOME/.config" "$HOME/.local/share" "$HOME")
#fi

# Self-management utilities
# Install, update, or remove this script as a system command.
#
# Install paths:
#   root → /usr/local/bin/luminova  (requires root)
#   user → ~/.local/bin/luminova    (user-space, no root needed)

# Print the absolute install path for the given runtime mode
config_script_target_bin() {
    local runtime="${1:-root}"
    local dir

    # 1. Prefer directories already in PATH
    for dir in "${COMMON_PATHS[@]}"; do
        if _in_executable_path "$dir" && [ -d "$dir" ] && [ -w "$dir" ]; then
            printf "%s/luminova\n" "$dir"
            return 0
        fi
    done

    # 2. Fallback by runtime
    case "$runtime" in
        root)
            printf "/usr/local/bin/luminova\n"
            return 0
            ;;
        user)
            printf "%s/.local/bin/luminova\n" "$HOME"
            return 0
            ;;
        *)
            _print "Invalid runtime: $runtime (expected: root|user)" error 1
            return 1
            ;;
    esac
}

config_path() {
    local path dir fallback=""

    if [ -n "$TMP_CONFIG_DIR" ]; then
        printf "%s\n" "$TMP_CONFIG_DIR"
        return 0
    fi

    for dir in "${CONFIGURATION_PATHS[@]}"; do
        if _is_path_rw "$dir"; then
            if [[ "$dir" == "$HOME"* ]]; then
                path="$dir/.luminova"
            else
                path="$dir/luminova"
            fi

            TMP_CONFIG_DIR="$path"
            printf "%s\n" "$path"

            return 0
        fi

        # store first valid dir as fallback
        [ -z "$fallback" ] && [ -d "$dir" ] && [ -w "$dir" ]  && fallback="$dir"
    done

    # fallback if nothing writable
    if [ -n "$fallback" ]; then
        if [[ "$fallback" == "$HOME"* ]]; then
            path="$fallback/.luminova"
        else
            path="$fallback/luminova"
        fi

        TMP_CONFIG_DIR="$path"
        printf "%s\n" "$path"

        return 0
    fi

    return 1
}

config_get_file() {
    local check="${1:-0}"
    local dir conf_dir conf_file

    if [ -n "$TMP_CONFIG_FILE" ]; then
        printf "%s\n" "$TMP_CONFIG_FILE"
        return 0
    fi

    conf_dir="$(config_path)" || {
        return 1
    }

    mkdir -p "$conf_dir" || {
        _print "Failed to create config directory: $conf_dir" error 0 1
        return 1
    }

    conf_file="$conf_dir/vci.conf"

    if [ "$check" -eq 1 ] && [ ! -f "$conf_file" ]; then
        return 1
    fi

    TMP_CONFIG_FILE="$conf_file"

    printf "%s\n" "$conf_file"
    return 0
}

#value="$(config_get LUMINOVA_VCI_BIN)"
#echo "$value"
config_get() {
    local find="${1:-}"
    local conf_file="${2:-$(config_get_file)}"
    local line key value

    [ -f "$conf_file" ] || return 1

    # return ALL config
    if [ -z "$find" ]; then
        while IFS= read -r line; do
            case "$line" in
                *=*) printf "%s\n" "$line" ;;
            esac
        done < "$conf_file"
        return 0
    fi

    # return single key
    while IFS='=' read -r key value; do
        if [ "$key" = "$find" ]; then
            printf "%s\n" "$value"
            return 0
        fi
    done < "$conf_file"

    return 1
}

config_write() {
    local conf_target="$1"
    shift

    local conf_dir conf_file conf_name tmp_file tmp2 item key value

    [ -n "$conf_target" ] || {
        _print "Config path is empty" error 1 1
        return 1
    }

    # Reject writes with a blank value for the key the PHP UI depends on
    for item in "$@"; do
        case "$item" in
            LUMINOVA_PACKAGE_DIR=)
                _print "Refusing to write empty LUMINOVA_PACKAGE_DIR to config" error 1 1
                return 1
                ;;
        esac
    done

    conf_file="$conf_target"

    if [ -f "$conf_target" ]; then
       conf_file="$conf_target"
    elif [ -d "$conf_target" ]; then
       conf_file="$conf_target/vci.conf"
    elif [[ "$conf_target" != *.* || "$conf_target" == */ ]]; then
        conf_file="${conf_target%/}/vci.conf"
    fi

    conf_dir="$(dirname "$conf_file")"
    conf_name="$(basename "$conf_file")"

    mkdir -p "$conf_dir" || {
        _print "Failed to create config directory: $conf_dir" error 1 1
        return 1
    }

    if [ -e "$conf_file" ]; then
        if [ ! -w "$conf_file" ]; then
            _print "Configuration file is not writable:" error 1
            _print "  $conf_file" plain
            return 1
        fi
    elif [ ! -w "$conf_dir" ]; then
        _print "Configuration directory is not writable:" error 1
        _print "  $conf_dir" plain
        return 1
    fi

    tmp_file="$(_make_temp file "$conf_dir" ".$conf_name")" || return 1

    # --- load existing file first ---
    if [ -f "$conf_file" ]; then
        cat "$conf_file" > "$tmp_file"
    else
        : > "$tmp_file"
    fi

    # --- apply updates ---
    for item in "$@"; do
        case "$item" in
            *=*)
                key="${item%%=*}"
                value="${item#*=}"

                # Use a separate mktemp for the awk output so an interrupted
                # write never leaves a stale .tmp file behind
                tmp2="$(_make_temp file "$conf_dir" ".$conf_name")" || { 
                    rm -f "$tmp_file"
                    return 1 
                }

                awk -F= -v k="$key" -v v="$value" '
                    BEGIN { updated=0 }
                    $1 == k { print k"="v; updated=1; next }
                    { print }
                    END { if (updated==0) print k"="v }
                ' "$tmp_file" > "$tmp2" && mv "$tmp2" "$tmp_file" || {
                    rm -f "$tmp2" "$tmp_file"
                    return 1
                }
                ;;
            *)
                _print "Skipping invalid entry: $item" warn
                ;;
        esac
    done

    # mv "$tmp_file" "$conf_file"
    cp "$tmp_file" "$conf_file" && rm -f "$tmp_file"
    chmod 644 "$conf_file" 2>/dev/null || true

    TMP_CONFIG_FILE=""
    TMP_CONFIG_DIR=""
    return 0
}

config_has() {
    local key="$1"
    local conf_file="${2:-$(config_get_file)}"

    [ -n "$key" ] || return 1
    [ -f "$conf_file" ] || return 1

    while IFS='=' read -r k _; do
        [ "$k" = "$key" ] && return 0
    done < "$conf_file"

    return 1
}

config_delete() {
    local key="$1"
    local conf_file="${2:-$(config_get_file)}"
    local tmp line k

    [ -n "$key" ] || return 1
    [ -f "$conf_file" ] || return 1

    tmp="$(_make_temp file "$conf_file" ".tmp.vci.conf")" || return 1

    while IFS= read -r line; do
        case "$line" in
            "$key="*) 
                # skip (delete)
                ;;
            *)
                printf "%s\n" "$line" >> "$tmp"
                ;;
        esac
    done < "$conf_file"

    mv "$tmp" "$conf_file"
    return 0
}

config_clear() {
    local conf_file="${1:-}"
    local target="${2:-file}"
    local silent="${3:-0}"

    if [ -z "$conf_file" ]; then
        if [ "$target" = "file" ]; then
            conf_file="$(config_get_file)" || return 1
        else
            conf_file="$(config_path)" || return 1
        fi
    fi

    if [ -z "$conf_file" ]; then
        [ "$silent" -eq 0 ] && _print "No config path resolved" error 1
        return 1
    fi

    if [ -f "$conf_file" ]; then
        rm -f "$conf_file" || {
            [ "$silent" -eq 0 ] && _print "Failed to remove file: $conf_file" error 1
            return 1
        }
    elif [ -d "$conf_file" ]; then
        rm -rf "$conf_file" || {
            [ "$silent" -eq 0 ] && _print "Failed to remove directory: $conf_file" error 1
            return 1
        }
    else
        [ "$silent" -eq 0 ] && _print "Config not found: $conf_file" warn 1
        return 1
    fi

    [ "$silent" -eq 0 ] && _print "Removed config: $conf_file" info 1
    return 0
}

# Append target_dir to PATH in the user's shell RC file (avoids duplicates)
config_add_global_path() {
    local target_dir="$1"
    local rc_file

    case "${SHELL##*/}" in
        zsh)  rc_file="$HOME/.zshrc" ;;
        bash) rc_file="$HOME/.bashrc" ;;
        *)    rc_file="$HOME/.profile" ;;
    esac

    if grep -qs "$target_dir" "$rc_file" 2>/dev/null; then
        _print "PATH already contains: $target_dir" info 1
        return 0
    fi

    {
        printf '\n# PHP Luminova (VCI)\n'
        printf 'export PATH="%s:$PATH"\n' "$target_dir"
    } >> "$rc_file"

    _print "Added to $rc_file (restart your shell or run: source $rc_file)" success 1
}