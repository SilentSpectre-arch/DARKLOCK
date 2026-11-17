#!/usr/bin/env bash


set -u

PASSPHRASE="hello this is a joke"

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd -P)" || SCRIPT_DIR="."
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "$SCRIPT_SOURCE")"

# --- state storage (remembers the original permissions) ----------------------
STATE_DIR="${TMPDIR:-/tmp}/jukeware-state"
if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
    STATE_DIR="$SCRIPT_DIR/.jukeware-state"
    mkdir -p "$STATE_DIR" 2>/dev/null || {
        echo "Error: cannot create a state directory." >&2
        exit 1
    }
fi

# --- colors (only when attached to a terminal) -------------------------------
if [ -t 1 ]; then
    C_RED=$'\033[1;31m'; C_GRN=$'\033[1;32m'; C_YEL=$'\033[1;33m'
    C_CYN=$'\033[1;36m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_B=""; C_0=""
fi

LOCKED_DIR=""

die() { printf '%sError:%s %s\n' "$C_RED" "$C_0" "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
JokeWare -- a harmless ransomware simulator (prank)

Usage:
  ./ransomware-prank.sh lock <folder>         lock a folder and show the ransom screen
  ./ransomware-prank.sh lock --stay <folder>  lock the folder and exit (leave it locked)
  ./ransomware-prank.sh                       re-show the ransom screen (unlocks on passphrase)
  ./ransomware-prank.sh unlock [folder]       manual unlock (prankster backdoor)
  ./ransomware-prank.sh help                  this help

The secret phrase is: hello this is a joke

Manual recovery that ALWAYS works:
  chmod 755 "/path/to/locked/folder"

This is a prank: only folder permissions are changed.
No file is ever encrypted, moved or deleted.
EOF
}

# --- helpers -----------------------------------------------------------------
is_protected() {
    local d="$1"
    case "$d" in
        /|/bin|/sbin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/libx32|/media|\
/mnt|/opt|/proc|/root|/run|/srv|/sys|/tmp|/usr|/var|/usr/local|/var/tmp)
            return 0 ;;
        /etc/*|/usr/*|/bin/*|/sbin/*|/lib/*|/boot/*|/root/*|/srv/*|/run/*|\
/proc/*|/sys/*|/dev/*|/var/*)
            return 0 ;;
    esac
    [ "$d" = "${HOME:-}" ] && return 0
    return 1
}

resolve_dir() {
    # Canonical path WITHOUT entering the folder (a locked chmod-000 folder
    # cannot be cd'd into, but stat/readlink from outside still work).
    local d="${1:-}" orig="${1:-}" r=""
    [ -n "$d" ] || die "no folder given. Usage: $SCRIPT_PATH lock <folder>"
    [ -d "$d" ] || die "not a folder: $orig"
    r="$(readlink -f -- "$d" 2>/dev/null)"
    if [ -z "$r" ]; then
        # fallback if readlink is unavailable: resolve the parent, append name
        local p b
        p="$(dirname -- "$d")"
        b="$(basename -- "$d")"
        r="$(cd -- "$p" >/dev/null 2>&1 && pwd -P)" || die "cannot access: $orig"
        r="$r/$b"
    fi
    [ -d "$r" ] || die "cannot resolve path: $orig (locked already? run: bash $SCRIPT_PATH unlock)"
    printf '%s' "$r"
}

hash_for() {
    local h
    h="$(printf '%s' "$1" | md5sum 2>/dev/null | cut -d' ' -f1)"
    if [ -z "$h" ]; then
        h="$(printf '%s' "$1" | sed 's#[/]#_#g; s#[[:space:]]#_#g')"
    fi
    printf '%s' "$h"
}

state_file() { printf '%s/%s.state' "$STATE_DIR" "$(hash_for "$1")"; }

save_state() {
    local f
    f="$(state_file "$1")"
    printf '%s\n%s\n' "$2" "$1" > "$f" || die "cannot write state file: $f"
}

read_state() {   # $1 = dir ; sets R_MODE and R_PATH ; returns 1 if no state
    local f
    f="$(state_file "$1")"
    [ -f "$f" ] || return 1
    R_MODE="$(head -n 1 "$f")"
    R_PATH="$(sed -n '2p' "$f")"
    return 0
}

clear_state() { rm -f -- "$(state_file "$1")"; }

script_conflict() {   # $1 = target dir ; true if script lives in/under/above it
    local d="$1"
    [ "$d" = "$SCRIPT_DIR" ] && return 0
    case "$d/" in "$SCRIPT_DIR"/*) return 0 ;; esac   # script inside target
    case "$SCRIPT_DIR/" in "$d"/*) return 0 ;; esac   # target above script
    return 1
}

# --- the show ----------------------------------------------------------------
banner() {
    cat <<'EOF'
   ██████╗   ██████╗   ██████╗  ███████╗
  ██╔═══██╗ ██╔═══██╗ ██╔═══██╗██╔════╝
  ██║   ██║ ██║   ██║ ███████╔╝███████╗
  ██║   ██║ ██║   ██║ ██╔══██╗ ╚════██╗
  ╚██████╔╝ ╚██████╔╝ ██║  ██║ ███████║
   ╚═════╝   ╚═════╝  ╚═╝  ╚═╝ ╚══════╝
EOF
}

ransom_note() {   # $1 = dir, $2 = item count, $3 = original mode
    local items="items are"
    [ "$2" = "1" ] && items="item is"
    cat <<EOF
${C_RED}${C_B}
  +----------------------------------------------------------------------+
  |            !!!  OFFICIAL RANSOM NOTICE -- JOKEWARE GANG  !!!         |
  +----------------------------------------------------------------------+${C_0}

  Your folder has been locked by the feared JOKEWARE gang:

      ${C_CYN}$1${C_0}

  $2 ${items} being held hostage. Sort of. Not really.
  In fact we changed exactly ONE thing: the folder's Unix permissions
  (it was ${C_YEL}$3${C_0}, now it is ${C_YEL}000${C_0}). Every file inside is 100%
  untouched and safe. We are ransomware in the same sense a banana
  is a telephone.

  ${C_B}THE RANSOM${C_0}
  To unlock, type the secret phrase -- the ancient words that every
  victim somehow always knows:

      ${C_GRN}${C_B}hello this is a joke${C_0}

  (yes, that is literally it. We did say this was a prank.)

  ${C_B}WHAT WE DEMAND${C_0}
  Nothing. A tiny smile would be nice. Definitely no bitcoin.
  Wallet: bc1q-not-a-real-address-this-is-a-prank

  ${C_B}IF YOU REFUSE${C_0}
  Absolutely nothing will happen, forever. But your friendly
  neighborhood prankster can always unlock it:

      bash $SCRIPT_PATH unlock
EOF
}

fake_encrypt() {   # $@ = file names collected BEFORE the folder was locked
    printf '%s  -- "ENCRYPTING" YOUR FILES --%s\n' "$C_YEL" "$C_0"
    printf '  (spoiler: this only changes one folder permission)\n\n'
    if [ "$#" -eq 0 ]; then
        printf '    Encrypting... nothing? The folder is empty. Bold move.\n\n'
        return 0
    fi
    local n j
    for n in "$@"; do
        printf '    %-30s ' "$n"
        for j in 1 2 3 4 5 6 7 8 9 10; do
            printf '%s' '█'
            sleep 0.02
        done
        printf ' 100%%\n'
    done
    printf '\n    Done. 0 bytes written, 0 files modified. Shhh.\n\n'
}

do_unlock() {   # $1 = dir, $2 = mode to restore, $3 = "passphrase" or "backdoor"
    local dir="$1" mode="$2"
    if chmod "$mode" "$dir" 2>/dev/null; then
        clear_state "$dir"
        local how
        if [ "$3" = "passphrase" ]; then
            how=$(printf '  Passphrase accepted: "%s"\n' "$PASSPHRASE")
        else
            how='  Manual unlock performed (prankster backdoor).'
        fi
        printf '%s
  ============================================================
     ***  UNLOCKED! THE PROPHECY IS FULFILLED  ***
  ============================================================%s

%s
  Folder permissions restored to %s%s%s: %s

  Reminder: nothing was EVER encrypted, moved or deleted.
  JokeWare thanks you for your cooperation. :)
' "$C_GRN" "$C_0" "$how" "$C_YEL" "$mode" "$C_0" "$dir"
        return 0
    fi
    printf '%schmod failed -- unlock manually with:  sudo chmod %s "%s"%s\n' \
        "$C_RED" "$mode" "$dir" "$C_0"
    return 1
}

prompt_loop() {   # $1 = dir, $2 = original mode, $3 = item count
    local dir="$1" mode="$2" count="$3"
    LOCKED_DIR="$dir"
    banner
    ransom_note "$dir" "$count" "$mode"

    local attempts=0 answer norm
    local taunts=(
        "Nope. (Hint: it is literally printed in the ransom note above.)"
        "Wrong! The files remain... exactly as safe as before. Terrifying, right?"
        "Access denied. The ancient prophecy remains unfulfilled."
        "Incorrect. The banana is still not a telephone. Try again."
    )

    while :; do
        printf '%sEnter the passphrase to decrypt your files: %s' "$C_B" "$C_0"
        answer=""
        if ! IFS= read -r answer; then
            printf '\n%sNo input received -- the folder stays LOCKED.%s\n' "$C_YEL" "$C_0"
            printf 'Unlock later:    bash %s unlock "%s"\n' "$SCRIPT_PATH" "$dir"
            printf 'Manual unlock:   chmod %s "%s"\n' "$mode" "$dir"
            return 1
        fi
        norm="$(printf '%s' "$answer" \
            | tr '[:upper:]' '[:lower:]' \
            | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//' -e 's/\r$//')"
        if [ "$norm" = "$PASSPHRASE" ] \
           || [ "$(printf '%s' "$norm" | tr -d ' ')" = "hellothisisajoke" ]; then
            do_unlock "$dir" "$mode" passphrase
            return 0
        fi
        printf '%s%s%s\n' "$C_RED" "${taunts[$((attempts % ${#taunts[@]}))]}" "$C_0"
        attempts=$((attempts + 1))
    done
}

# --- commands ----------------------------------------------------------------
cmd_lock() {
    local stay=0
    if [ "${1:-}" = "--stay" ]; then
        stay=1
        shift
    fi
    local dir
    dir="$(resolve_dir "${1:-}")" || return 1

    if is_protected "$dir"; then
        die "refusing to lock '$dir' -- it is a system folder (safety guard). Pick a folder you own, like ~/Desktop/stuff"
    fi
    if script_conflict "$dir"; then
        die "refusing to lock '$dir' -- this script must stay outside (and not above) the locked folder, or you could not unlock it."
    fi
    if [ -e "$(state_file "$dir")" ]; then
        die "'$dir' is already JokeWare-locked. Unlock it first: bash $SCRIPT_PATH unlock"
    fi

    local mode
    mode="$(stat -c '%a' "$dir" 2>/dev/null)" || die "cannot read permissions of: $dir"
    if [ "$mode" = "0" ]; then
        die "folder '$dir' already has no permissions (mode 0) -- refusing."
    fi

    # read-only look inside, BEFORE the door closes
    local count children=() p
    count="$(find "$dir" -mindepth 1 -maxdepth 3 2>/dev/null | wc -l | tr -d ' ')"
    while IFS= read -r p; do
        children+=("$(basename -- "$p")")
        [ "${#children[@]}" -ge 8 ] && break
    done < <(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null)

    save_state "$dir" "$mode"
    if ! chmod 000 "$dir" 2>/dev/null; then
        clear_state "$dir"
        die "chmod failed on '$dir' (not the owner?). Nothing was changed."
    fi
    LOCKED_DIR="$dir"

    printf '%sLOCKED:%s %s\n' "$C_RED" "$C_0" "$dir"
    printf 'Permissions changed: %s -> 000 (files inside: untouched)\n' "$mode"
    printf '%sPanic recovery (always works):%s chmod %s "%s"\n\n' \
        "$C_YEL" "$C_0" "$mode" "$dir"

    if [ "$stay" -eq 1 ]; then
        printf 'Leaving it locked. To show the ransom screen again:\n'
        printf '    bash %s\n' "$SCRIPT_PATH"
        return 0
    fi

    fake_encrypt "${children[@]}"
    prompt_loop "$dir" "$mode" "$count"
}

cmd_unlock() {
    local dir="${1:-}"
    if [ -z "$dir" ]; then
        local f first="" n=0
        for f in "$STATE_DIR"/*.state; do
            [ -f "$f" ] || continue
            n=$((n + 1))
            [ -z "$first" ] && first="$f"
        done
        if [ "$n" -eq 0 ]; then
            printf 'Nothing is currently JokeWare-locked.\n'
            printf '(If a folder still looks locked, unlock manually: chmod 755 <folder>)\n'
            return 0
        fi
        if [ "$n" -gt 1 ]; then
            printf '%sSeveral locked folders:%s\n' "$C_YEL" "$C_0"
            for f in "$STATE_DIR"/*.state; do
                [ -f "$f" ] && printf '  %s\n' "$(sed -n '2p' "$f")"
            done
            die "pick one: bash $SCRIPT_PATH unlock <folder>"
        fi
        dir="$(sed -n '2p' "$first")"
    fi

    dir="$(resolve_dir "$dir")" || return 1
    local mode=""
    if read_state "$dir"; then
        mode="$R_MODE"
    else
        mode="755"
        printf '%sWarning:%s no saved state -- restoring default 755 (original may differ).\n' \
            "$C_YEL" "$C_0" >&2
    fi
    LOCKED_DIR="$dir"
    do_unlock "$dir" "$mode" backdoor
}

cmd_resume() {
    local f first="" n=0
    for f in "$STATE_DIR"/*.state; do
        [ -f "$f" ] || continue
        n=$((n + 1))
        [ -z "$first" ] && first="$f"
    done
    if [ "$n" -eq 0 ]; then
        printf 'Nothing is currently JokeWare-locked.\n\n'
        usage
        return 0
    fi
    if [ "$n" -gt 1 ]; then
        printf '%sSeveral locked folders:%s\n' "$C_YEL" "$C_0"
        for f in "$STATE_DIR"/*.state; do
            [ -f "$f" ] && printf '  %s\n' "$(sed -n '2p' "$f")"
        done
        die "pick one: bash $SCRIPT_PATH unlock <folder>"
    fi
    local dir mode
    dir="$(sed -n '2p' "$first")"
    [ -d "$dir" ] || die "locked folder '$dir' no longer exists."
    mode="$(head -n 1 "$first")"
    local count
    count="$(find "$dir" -mindepth 1 -maxdepth 3 2>/dev/null | wc -l | tr -d ' ')"
    prompt_loop "$dir" "$mode" "$count"
}

# --- main --------------------------------------------------------------------
trap 'printf "\n"; if [ -n "$LOCKED_DIR" ]; then printf "%sPrank interrupted -- folder stays LOCKED:%s %s\n" "$C_YEL" "$C_0" "$LOCKED_DIR"; printf "Unlock later:   bash %s unlock \"%s\"\n" "$SCRIPT_PATH" "$LOCKED_DIR"; printf "Manual unlock:  chmod 755 \"%s\" (or the original mode shown on the lock screen)\n" "$LOCKED_DIR"; fi; exit 130' INT

case "${1:-}" in
    lock)          shift; cmd_lock "$@" ;;
    unlock)        shift; cmd_unlock "$@" ;;
    help|-h|--help) usage ;;
    "")            cmd_resume ;;
    *)             die "unknown command: $1 (try: $SCRIPT_PATH help)" ;;
esac
