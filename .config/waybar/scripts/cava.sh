#! /bin/bash

export LC_ALL="${LC_ALL:-C.UTF-8}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

dict="s/;//g;s/0/▁/g;s/1/▂/g;s/2/▃/g;s/3/▄/g;s/4/▅/g;s/5/▆/g;s/6/▇/g;s/7/█/g;"

AUDIO_SOURCE=$(pactl info 2>/dev/null | awk '/Default Sink:/{print $3".monitor"}')
[ -z "$AUDIO_SOURCE" ] && AUDIO_SOURCE="auto"

config_file="/tmp/waybar_cava_config_$$"
echo "
[general]
bars = 12

[input]
method = pulse
source = $AUDIO_SOURCE

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
" > "$config_file"

trap "rm -f $config_file" EXIT

cava -p "$config_file" 2>/dev/null | while read -r line; do
    # Si Waybar dejo de leer esta salida (por ejemplo, porque la barra se
    # relanzo), el pipe esta roto. Sin esto el bucle sigue girando con cava
    # alimentandolo y solo escribe "Broken pipe" en el log de Waybar.
    echo "$line" | sed "$dict" 2>/dev/null || break
done
