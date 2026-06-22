#!/bin/sh
set -eu

hold=0
case "${1:-}" in
  --hold)
    hold=1
    ;;
  "")
    ;;
  *)
    echo "usage: $0 [--hold]" >&2
    exit 64
    ;;
esac

engine_root="/home/aik/Projects/LuaProjects/Kristal"
mod_id="deltarune-ddd-ch1"
title="Kristal - ${mod_id}"

if [ ! -d "$engine_root" ]; then
  echo "Kristal engine not found: $engine_root" >&2
  exit 1
fi

if [ ! -f "$engine_root/main.lua" ]; then
  echo "Kristal engine main.lua not found: $engine_root/main.lua" >&2
  exit 1
fi

if [ "$hold" -eq 1 ]; then
  shell_cmd='cd "$1"; love "$1" --mod "$2" --auto-mod-start; exit_code=$?; echo; echo love exited with status $exit_code; exec zsh -l'
else
  shell_cmd='cd "$1"; exec love "$1" --mod "$2" --auto-mod-start'
fi

terminal=""
if [ -n "${KITTY_WINDOW_ID:-}" ] || [ "${TERM:-}" = "xterm-kitty" ]; then
  terminal="kitty"
elif [ -n "${XTERM_VERSION:-}" ]; then
  terminal="xterm"
else
  case "${TERM:-}" in
    xterm|xterm-*)
      terminal="xterm"
      ;;
  esac
fi

case "$terminal" in
  kitty)
    if [ "$hold" -eq 1 ]; then
      kitty --detach --hold --title "$title" --directory "$engine_root" zsh -lc "$shell_cmd" sh "$engine_root" "$mod_id" >/dev/null 2>&1
      exit 0
    fi
    kitty --detach --title "$title" --directory "$engine_root" zsh -lc "$shell_cmd" sh "$engine_root" "$mod_id" >/dev/null 2>&1
    exit 0
    ;;
  xterm)
    if [ "$hold" -eq 1 ]; then
      xterm -hold -T "$title" -e zsh -lc "$shell_cmd" sh "$engine_root" "$mod_id" >/dev/null 2>&1 &
      exit 0
    fi
    xterm -T "$title" -e zsh -lc "$shell_cmd" sh "$engine_root" "$mod_id" >/dev/null 2>&1 &
    exit 0
    ;;
  *)
    echo "unsupported terminal: TERM=${TERM:-}, KITTY_WINDOW_ID=${KITTY_WINDOW_ID:-}, XTERM_VERSION=${XTERM_VERSION:-}" >&2
    exit 1
    ;;
esac
