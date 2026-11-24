# Usage: osu-lazer-launcher [OSU ARGS...]
#
# Picks an ALSA playback device, a sample rate and a period size, points osu
# at the device, takes its card from PipeWire, and runs osu ($OSU_GAME, set by
# the package). The card goes back to PipeWire when the game exits.
#
# These variables skip their menu:
#   OSU_LATENCY_TWEAKER_CARD=ID[,DEV]  (e.g. DX1 or DX1,0)
#   OSU_LATENCY_TWEAKER_FREQ=HZ        (e.g. 192000)
#   OSU_LATENCY_TWEAKER_PERIOD=N       (-N: N samples, N: N ms)
# Without a terminal, the remembered picks are used. The audio device must
# then be remembered (or set) and plugged in.

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/osu-latency-tweaker"
# Remembered picks, written by the menus.
SAVED="$STATE/soundcard" # "<card id> <device>"
SAVED_FREQ="$STATE/freq"
SAVED_PERIOD="$STATE/period"
# basscallwrap uses these when the variables are not set.
DEFAULT_FREQ=44100
DEFAULT_PERIOD=-256
# osu-framework keeps its settings, the audio device among them, here.
FRAMEWORK_INI="${XDG_DATA_HOME:-$HOME/.local/share}/osu/framework.ini"

info() { printf 'osu-latency-tweaker: %s\n' "$*" >&2; }
die() {
  info "$*"
  exit 1
}

# --- menus ------------------------------------------------------------------

have_terminal() { [ -t 0 ] && [ -t 2 ]; }

# menu PROMPT CURRENT KEY DESC [KEY DESC]... -> PICKED (a KEY).
# Menu lines are "<key>  <desc>", keys padded to one width. The cursor starts
# on CURRENT.
# With MENU_CUSTOM=1, Enter on typed text that matches no line picks the text.
menu() {
  local prompt="$1" current="$2" keys=() lines=() width=0 i at=0 choice footer bind=()
  shift 2
  while [ "$#" -ge 2 ]; do
    keys+=("$1")
    lines+=("$2")
    shift 2
  done
  for i in "${!keys[@]}"; do
    [ "${#keys[i]}" -le "$width" ] || width="${#keys[i]}"
  done
  for i in "${!keys[@]}"; do
    lines[i]="$(printf '%-*s  %s' "$width" "${keys[i]}" "${lines[i]}")"
  done
  for i in "${!keys[@]}"; do
    if [ "${keys[i]}" = "$current" ]; then
      at="$i"
      break
    fi
  done

  footer='↑/↓ move   Enter pick   Esc cancel   type to filter'
  if [ "${MENU_CUSTOM:-}" = 1 ]; then
    footer="$footer (or a value of your own)"
    bind=(--bind 'enter:accept-or-print-query')
  fi
  choice="$(printf '%s\n' "${lines[@]}" | fzf --prompt="$prompt> " --height=~100% --reverse \
    --footer="$footer" --bind "load:pos($((at + 1)))" "${bind[@]}")" || die "nothing picked"
  PICKED="${choice%%  *}"
  PICKED="${PICKED%% *}"
}

# remember FILE OLD NEW WHAT: writes NEW to FILE if it is not OLD.
remember() {
  [ "$3" != "$2" ] || return 0
  mkdir -p "$STATE"
  printf '%s\n' "$3" >"$1"
  info "remembered your $4: ${3/ /,}"
}

# --- sound cards ------------------------------------------------------------

# One line per playback device, tab-separated:
# "<card id>,<device>  <card number>  <BASS device name>".
# BASS names a device "<card name>: <pcm name>", the bracketed parts of:
#   card 3: DX1 [DX1], device 0: USB Audio [USB Audio]
list_devices() {
  local line re='^card ([0-9]+): ([^ ]+) \[([^]]*)\], device ([0-9]+): .* \[([^]]*)\]$'
  aplay -l 2>/dev/null | while IFS= read -r line; do
    [[ $line =~ $re ]] || continue
    printf '%s,%s\t%s\t%s: %s\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]}" \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[5]}"
  done
}

# Sets KEY ("<card id>,<device>").
pick_device() {
  local saved="" saved_dev="" args=() key idx name
  if [ -r "$SAVED" ]; then read -r saved saved_dev <"$SAVED" || true; fi
  saved="$saved${saved_dev:+,$saved_dev}"

  # Without a menu, never fall back to another card: it can be the one the
  # desktop plays on. resolve_device stops if the card is unplugged.
  if ! have_terminal; then
    [ -n "$saved" ] ||
      die "no remembered audio device: start osu once from a terminal, or set OSU_LATENCY_TWEAKER_CARD"
    KEY="$saved"
    return 0
  fi

  while IFS=$'\t' read -r key idx name; do
    args+=("$key" "$name")
  done < <(list_devices)
  [ "${#args[@]}" -gt 0 ] || die "no sound cards found (aplay -l lists nothing)"

  menu 'audio device' "$saved" "${args[@]}"
  KEY="$PICKED"
  remember "$SAVED" "${saved/,/ }" "${KEY/,/ }" "audio device"
}

# --- sample rate and period size --------------------------------------------

# pick_number VAR FILE WHAT DEFAULT CHECK RANGE DESCRIBE VALUE...
# Exports VAR: the pick from a menu of the VALUEs, or without a terminal the
# remembered pick. A VAR that is set already only gets checked.
# CHECK VALUE tells if VALUE is in RANGE (a text for messages).
# DESCRIBE VALUE prints a line about VALUE.
# The cursor starts on the remembered pick, or else on DEFAULT.
pick_number() {
  local var="$1" file="$2" what="$3" default="$4" check="$5" range="$6" describe="$7"
  local saved="" v args=()
  shift 7
  if [ -n "${!var:-}" ]; then
    "$check" "${!var}" || die "$var=${!var} is not a $what in $range"
    return 0
  fi
  if [ -r "$file" ]; then read -r saved <"$file" || true; fi
  # The file goes into shell arithmetic later: never trust its text.
  if [ -n "$saved" ] && ! "$check" "$saved"; then
    info "ignoring the remembered $what \"$saved\": not in $range"
    saved=""
  fi

  if have_terminal; then
    # A value of your own from an earlier run goes on the list too.
    if [ -n "$saved" ] && [[ " $* " != *" $saved "* ]]; then set -- "$saved" "$@"; fi
    for v in "$@"; do args+=("$v" "$("$describe" "$v")"); done
    MENU_CUSTOM=1 menu "$what" "${saved:-$default}" "${args[@]}"
    "$check" "$PICKED" || die "\"$PICKED\" is not a $what in $range"
    remember "$file" "$saved" "$PICKED" "$what"
  elif [ -n "$saved" ]; then
    PICKED="$saved"
  else
    return 0
  fi
  export "$var=$PICKED"
}

# Values outside these ranges fail in BASS or crackle loudly.
FREQ_RANGE="8000..384000 Hz"
PERIOD_RANGE="-8192..-8 samples or 1..100 ms"

# The regex comes first: shell arithmetic runs code hidden in other text.
# shellcheck disable=SC2329 # called by pick_number
check_freq() { [[ $1 =~ ^[1-9][0-9]{3,5}$ ]] && [ "$1" -ge 8000 ] && [ "$1" -le 384000 ]; }

# shellcheck disable=SC2329 # called by pick_number
check_period() {
  [[ $1 =~ ^-?[1-9][0-9]{0,3}$ ]] || return 1
  if [ "$1" -lt 0 ]; then
    [ "$1" -ge -8192 ] && [ "$1" -le -8 ]
  else
    [ "$1" -le 100 ]
  fi
}

# shellcheck disable=SC2329 # called by pick_number
describe_freq() { echo "Hz"; }

# ms SAMPLES FREQ: prints the length in ms, e.g. "1.33 ms".
# shellcheck disable=SC2329 # called by describe_period
ms() {
  local cms=$((($1 * 100000 + $2 / 2) / $2)) # hundredths of a ms, rounded
  printf '%d.%02d ms' "$((cms / 100))" "$((cms % 100))"
}

# shellcheck disable=SC2329 # called by pick_number
# Uses the picked sample rate. BASS makes the buffer twice the period.
describe_period() {
  local freq="${OSU_LATENCY_TWEAKER_FREQ:-$DEFAULT_FREQ}"
  if [ "$1" -lt 0 ]; then
    echo "$((-$1)) samples = $(ms $((-$1)) "$freq") period," \
      "$(ms $((-$1 * 2)) "$freq") buffer at $freq Hz"
  else
    echo "$1 ms period, $(($1 * 2)) ms buffer"
  fi
}

pick_freq() {
  pick_number OSU_LATENCY_TWEAKER_FREQ "$SAVED_FREQ" "sample rate" 48000 \
    check_freq "$FREQ_RANGE" describe_freq 192000 96000 48000 44100
}

pick_period() {
  pick_number OSU_LATENCY_TWEAKER_PERIOD "$SAVED_PERIOD" "period size" "$DEFAULT_PERIOD" \
    check_period "$PERIOD_RANGE" describe_period -16 -32 -64 -128 -256 -512 -1024
}

# KEY -> CARD_INDEX and BASS_NAME. Warns when an earlier device has the same
# BASS name: osu picks the first device with that name.
resolve_device() {
  local key idx name earlier=()
  CARD_INDEX="" BASS_NAME=""
  while IFS=$'\t' read -r key idx name; do
    if [ "$key" = "$KEY" ]; then
      CARD_INDEX="$idx" BASS_NAME="$name"
      break
    fi
    earlier+=("$name")
  done < <(list_devices)
  [ -n "$CARD_INDEX" ] || die "no playback device $KEY (see aplay -l)"
  for name in "${earlier[@]}"; do
    if [ "$name" = "$BASS_NAME" ]; then
      info "warning: an earlier device has the same name \"$BASS_NAME\"; osu plays on that one"
      break
    fi
  done
}

# Points osu at BASS_NAME. osu reads the file on start and writes it on exit.
# A symlinked file gets edited at its target, so the symlink stays.
set_osu_device() {
  local ini line found=0
  ini="$(realpath -m "$FRAMEWORK_INI")"
  mkdir -p "$(dirname "$ini")"
  TMP="$(mktemp "$ini.XXXXXX")" || die "cannot write $ini"
  chmod 644 "$TMP" # mktemp makes it 0600
  if [ -f "$ini" ]; then
    chmod --reference="$ini" "$TMP"
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ $line =~ ^[[:space:]]*AudioDevice[[:space:]]*= ]]; then
        line="AudioDevice = $BASS_NAME"
        found=1
      fi
      printf '%s\n' "$line"
    done <"$ini" >"$TMP"
  fi
  [ "$found" = 1 ] || printf 'AudioDevice = %s\n' "$BASS_NAME" >>"$TMP"
  mv "$TMP" "$ini"
  TMP=""
}

# --- taking the card from PipeWire ------------------------------------------
# Same as pavucontrol -> Configuration -> Off: PipeWire closes the card and
# desktop audio keeps going on the other cards. The old profile comes back on
# exit. Without PipeWire, only the busy check runs.

PW_DEVICE="" PW_NAME="" PW_PROFILE=""

take_card() {
  local dump="" off profile free=0 pcms
  dump="$(pw-dump 2>/dev/null)" || dump=""
  if [ -n "$dump" ]; then
    PW_DEVICE="$(jq -r --arg c "$CARD_INDEX" 'first(.[]
      | select(.type == "PipeWire:Interface:Device"
        and (.info.props["alsa.card"] | tostring) == $c) | .id) // empty' <<<"$dump")"
  fi
  if [ -n "$PW_DEVICE" ]; then
    PW_NAME="$(jq -r --argjson d "$PW_DEVICE" 'first(.[] | select(.id == $d)
      | .info.props["device.name"]) // empty' <<<"$dump")"
    off="$(jq -r --argjson d "$PW_DEVICE" 'first(.[] | select(.id == $d)
      | .info.params.EnumProfile[]? | select(.name == "off") | .index) // empty' <<<"$dump")"
    profile="$(jq -r --argjson d "$PW_DEVICE" 'first(.[] | select(.id == $d)
      | .info.params.Profile[0].index) // empty' <<<"$dump")"
    # Already off, or no off profile: nothing to restore.
    if [ -n "$off" ] && [ -n "$profile" ] && [ "$profile" != "$off" ]; then
      PW_PROFILE="$profile"
      wpctl set-profile "$PW_DEVICE" "$off"
    fi
  fi

  # PipeWire closes the device asynchronously.
  pcms="/dev/snd/pcmC${CARD_INDEX}D${KEY#*,}p"
  for _ in $(seq 30); do
    if ! fuser -s "$pcms" 2>/dev/null; then
      free=1
      break
    fi
    sleep 0.1
  done
  if [ "$free" = 0 ]; then
    info "$KEY is in use by:"
    fuser -v "$pcms" 2>&1 | tail -n +2 >&2 || true
    die "close those programs and try again"
  fi
}

# Looks the card up again by name: after a PipeWire restart, its old id can
# belong to another object.
# shellcheck disable=SC2329 # called by cleanup
give_card_back() {
  local id=""
  [ -n "$PW_PROFILE" ] || return 0
  if [ -n "$PW_NAME" ]; then
    id="$(pw-dump 2>/dev/null | jq -r --arg n "$PW_NAME" 'first(.[]
      | select(.type == "PipeWire:Interface:Device" and .info.props["device.name"] == $n)
      | .id) // empty')" || id=""
  fi
  if [ -z "$id" ] || ! wpctl set-profile "$id" "$PW_PROFILE" 2>/dev/null; then
    info "could not give $KEY back to PipeWire; turn it on in pavucontrol -> Configuration"
  fi
  PW_PROFILE=""
}

# shellcheck disable=SC2329 # called from the EXIT trap
cleanup() {
  [ -z "$TMP" ] || rm -f "$TMP"
  give_card_back
}

# --- main -------------------------------------------------------------------

TMP="" # half-written framework.ini
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [ -n "${OSU_LATENCY_TWEAKER_CARD:-}" ]; then
  KEY="$OSU_LATENCY_TWEAKER_CARD"
  [[ $KEY == *,* ]] || KEY="$KEY,0"
else
  pick_device
fi
resolve_device
set_osu_device
pick_freq
pick_period

take_card
info "playing on $KEY ($BASS_NAME) at ${OSU_LATENCY_TWEAKER_FREQ:-$DEFAULT_FREQ} Hz," \
  "period ${OSU_LATENCY_TWEAKER_PERIOD:-$DEFAULT_PERIOD}; nothing else can use it until the game closes"

# Bash runs a trap only after a foreground command ends. `wait` returns at
# once on a trapped signal, so the signal goes on to the game and the loop
# waits until the game is gone before the EXIT trap gives the card back.
"$OSU_GAME" "$@" &
child=$!
trap 'kill -INT "$child" 2>/dev/null || true' INT
trap 'kill -TERM "$child" 2>/dev/null || true' TERM HUP
while kill -0 "$child" 2>/dev/null; do
  wait "$child" || true
done
status=0
wait "$child" || status=$?
exit "$status"
