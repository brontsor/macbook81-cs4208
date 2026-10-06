#!/bin/bash
# mb81-jack-switch — MacBook8,1 (CS4208) headphone-jack auto-switch.
#
# The codec path is the 0x02-only prepare in macbook81-cs4208. A headphone
# open must not rewrite converter 0x0a. This watcher only moves the route.
# It does not restart WirePlumber. That restart was the old workaround for
# the tag clobber, and it left the playing stream on the headphone nick.
#
# The card runs in raw-PCM mode, so PipeWire has no ACP jack route.
#   plugged   -> default and playing streams = headphone PCM
#   unplugged -> default and playing streams = speaker EQ
#
# Do not move the EQ chain's own stream. Its media.name is
# "MacBook Speaker (EQ) output" and its target is MacBook_Speaker_Raw.
#
# Runs as a systemd --user service. Overridable via env:
# MB81_CARD_ID, MB81_HP_SINK, MB81_SPK_SINK.

set -u

CARD_ID="${MB81_CARD_ID:-PCH}"
HP_SINK="${MB81_HP_SINK:-alsa_output.pci-0000_00_1b.0.playback.0.0}"
SPK_SINK="${MB81_SPK_SINK:-input.MacBook_Speaker}"
EQ_MEDIA="MacBook Speaker (EQ) output"

log() { printf 'mb81-jack-switch: %s\n' "$*"; }

card_index() {
    awk -v id="$CARD_ID" '$0 ~ ("HDA Intel " id "$") {print $1; exit}' \
        /proc/asound/cards
}

jack_numid() {
    amixer -c "$1" controls 2>/dev/null \
        | sed -n "s/numid=\([0-9]*\).*name='Headphone Jack'.*/\1/p" | head -1
}

jack_state() {
    amixer -c "$1" cget numid="$2" 2>/dev/null \
        | sed -n 's/.*: values=\(on\|off\).*/\1/p' | head -1
}

set_default() {
    pw-metadata -n default 0 default.configured.audio.sink \
        "{ \"name\": \"$1\" }" >/dev/null 2>&1
}

node_exists() {
    pw-cli ls Node 2>/dev/null | grep -q "node.name = \"$1\""
}

# Move application streams onto $1. Skip the EQ chain's internal link.
move_streams() {
    local sink="$1" id="" media="" app="" line
    while IFS= read -r line; do
        case "$line" in
            *"Sink Input #"*)
                if [[ -n "$id" && "$media" != "$EQ_MEDIA" ]]; then
                    if pactl move-sink-input "$id" "$sink" >/dev/null 2>&1; then
                        log "moved $id (${app:-stream}) -> $sink"
                    else
                        log "move $id (${app:-stream}) -> $sink failed"
                    fi
                fi
                id="${line##*#}"
                media=""
                app=""
                ;;
            *"media.name = "*)
                media="${line#*\"}"
                media="${media%%\"*}"
                ;;
            *"application.name = "*)
                app="${line#*\"}"
                app="${app%%\"*}"
                ;;
        esac
    done < <(pactl list sink-inputs 2>/dev/null)
    if [[ -n "$id" && "$media" != "$EQ_MEDIA" ]]; then
        if pactl move-sink-input "$id" "$sink" >/dev/null 2>&1; then
            log "moved $id (${app:-stream}) -> $sink"
        else
            log "move $id (${app:-stream}) -> $sink failed"
        fi
    fi
}

apply() {  # $1 = on|off
    local sink
    if [[ "$1" == on ]]; then
        sink="$HP_SINK"
        log "headphones plugged -> $sink"
    else
        sink="$SPK_SINK"
        log "headphones unplugged -> $sink"
    fi
    for _ in $(seq 1 24); do
        node_exists "$sink" && break
        sleep 0.25
    done
    set_default "$sink"
    move_streams "$sink"
}

CARD="$(card_index)"
[[ -z "$CARD" ]] && { log "CS4208 card ($CARD_ID) not found; exiting"; exit 1; }
NUMID="$(jack_numid "$CARD")"
[[ -z "$NUMID" ]] && { log "Headphone Jack control not found on card $CARD; exiting"; exit 1; }
log "watching card $CARD 'Headphone Jack' (numid=$NUMID)"

last="$(jack_state "$CARD" "$NUMID")"
[[ -z "$last" ]] && { log "jack state unreadable; exiting"; exit 1; }
case "$last" in
    on) startup_sink="$HP_SINK" ;;
    *)  startup_sink="$SPK_SINK" ;;
esac
for _ in $(seq 1 24); do
    node_exists "$startup_sink" && break
    sleep 0.25
done
log "startup: $([ "$last" = on ] && echo headphones || echo speakers) -> $startup_sink"
set_default "$startup_sink"
move_streams "$startup_sink"

alsactl monitor "hw:$CARD" 2>/dev/null | while read -r _; do
    s="$(jack_state "$CARD" "$NUMID")"
    [[ -z "$s" || "$s" == "$last" ]] && continue
    last="$s"
    apply "$s"
done

log "alsactl monitor exited"
exit 1
