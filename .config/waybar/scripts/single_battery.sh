#!/bin/bash

# Single Battery Script (Combines all internal batteries: BAT0, BAT1, etc.)

ACTUAL_BATS=()
for b in /sys/class/power_supply/*; do
    [ -d "$b" ] || continue
    if [ "$(cat "$b/type" 2>/dev/null)" = "Battery" ]; then
        if [ -f "$b/scope" ] && grep -qi "device" "$b/scope"; then continue; fi
        ACTUAL_BATS+=("$b")
    fi
done

NUM_BATS=${#ACTUAL_BATS[@]}

# Detect AC charger
AC_ONLINE=0
for a in /sys/class/power_supply/*; do
    [ -d "$a" ] || continue
    atype=$(cat "$a/type" 2>/dev/null || true)
    if [ "$atype" = "Mains" ] || [ "$atype" = "USB" ] || [[ "$a" =~ (AC|ADP|ACAD) ]]; then
        if [ "$(cat "$a/online" 2>/dev/null)" = "1" ]; then
            AC_ONLINE=1
            break
        fi
    fi
done

if [ "$NUM_BATS" -eq 0 ]; then
    echo "{\"text\":\"󰚥\",\"tooltip\":\"Direct AC Power (Desktop Mode)\",\"class\":\"normal\"}"
    exit 0
fi

format_time() {
    local seconds=$1
    if [[ $seconds -le 0 ]]; then echo "N/A"; return; fi
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    if [[ $hours -gt 0 ]]; then printf "%dh %02dm" $hours $minutes; else printf "%dm" $minutes; fi
}

TOTAL_ENERGY_NOW=0
TOTAL_ENERGY_FULL=0
TOTAL_POWER_NOW=0
TOTAL_CAP=0
IS_CHARGING=false
TOOLTIP_BATS=""

for bat in "${ACTUAL_BATS[@]}"; do
    bname=$(basename "$bat")
    cap=$(cat "$bat/capacity" 2>/dev/null || echo "0")
    stat=$(cat "$bat/status" 2>/dev/null || echo "Unknown")
    en_now=$(cat "$bat/energy_now" 2>/dev/null || cat "$bat/charge_now" 2>/dev/null || echo "0")
    en_full=$(cat "$bat/energy_full" 2>/dev/null || cat "$bat/charge_full" 2>/dev/null || echo "0")
    pow_now=$(cat "$bat/power_now" 2>/dev/null || cat "$bat/current_now" 2>/dev/null || echo "0")

    TOTAL_ENERGY_NOW=$((TOTAL_ENERGY_NOW + en_now))
    TOTAL_ENERGY_FULL=$((TOTAL_ENERGY_FULL + en_full))
    TOTAL_POWER_NOW=$((TOTAL_POWER_NOW + pow_now))
    TOTAL_CAP=$((TOTAL_CAP + cap))

    [ "$stat" == "Charging" ] && IS_CHARGING=true
    TOOLTIP_BATS+="${bname}: ${cap}% (${stat})\\n"
done

if [[ $TOTAL_ENERGY_FULL -gt 0 ]]; then
    TOTAL_CAPACITY=$(( TOTAL_ENERGY_NOW * 100 / TOTAL_ENERGY_FULL ))
elif [[ $NUM_BATS -gt 0 ]]; then
    TOTAL_CAPACITY=$(( TOTAL_CAP / NUM_BATS ))
else
    TOTAL_CAPACITY=100
fi

if [[ $TOTAL_POWER_NOW -gt 0 ]] && [ "$IS_CHARGING" = false ] && [ "$AC_ONLINE" -eq 0 ]; then
    TOTAL_TIME_REMAINING=$((TOTAL_ENERGY_NOW * 3600 / TOTAL_POWER_NOW))
else
    TOTAL_TIME_REMAINING=0
fi

get_battery_icon() {
    local capacity=$1
    local is_chg=$2
    local ac_on=$3
    if [ "$is_chg" = true ]; then echo "󰂄";
    elif [ "$ac_on" -eq 1 ]; then echo "󰚥";
    elif [[ $capacity -ge 95 ]]; then echo "󰁹";
    elif [[ $capacity -ge 80 ]]; then echo "󰂂";
    elif [[ $capacity -ge 60 ]]; then echo "󰂁";
    elif [[ $capacity -ge 40 ]]; then echo "󰂀";
    elif [[ $capacity -ge 20 ]]; then echo "󰁿";
    else echo "󰁺"; fi
}

ICON=$(get_battery_icon "$TOTAL_CAPACITY" "$IS_CHARGING" "$AC_ONLINE")

if [ "$IS_CHARGING" = true ]; then
    STATUS="Charging"
    CLASS="charging"
elif [ "$AC_ONLINE" -eq 1 ]; then
    STATUS="Plugged in"
    CLASS="charging"
else
    STATUS="Discharging"
    if [[ $TOTAL_CAPACITY -le 15 ]]; then CLASS="critical";
    elif [[ $TOTAL_CAPACITY -le 30 ]]; then CLASS="warning";
    else CLASS="normal"; fi
fi

TIME_FORMATTED=$(format_time $TOTAL_TIME_REMAINING)
TOOLTIP="Battery Total: ${TOTAL_CAPACITY}%\\nTime: $TIME_FORMATTED\\nStatus: $STATUS\\n\\n${TOOLTIP_BATS}"
echo "{\"text\":\"$ICON ${TOTAL_CAPACITY}%\",\"tooltip\":\"$TOOLTIP\",\"class\":\"$CLASS\"}"
