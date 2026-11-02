# Language from ~/.config/locale.conf or /etc/locale.conf, unless already set.
if [ -z "${LANG:-}" ]; then
    if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/locale.conf" ]; then
        . "${XDG_CONFIG_HOME:-$HOME/.config}/locale.conf"
    elif [ -r /etc/locale.conf ]; then
        . /etc/locale.conf
    fi
fi
export LANG="${LANG:-C.UTF-8}"
