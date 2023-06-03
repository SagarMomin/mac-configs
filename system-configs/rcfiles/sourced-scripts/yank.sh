#!/bin/bash

## [yank STRING]
#  Tries to be a portable way to copy from a terminal to a clipboard
#
#  STRING   = Aribtrary text
#  RETURN  ->
#    [STRING] -> computer clipboard
function yank() {
  function is_app_installed() {
    type "$1" &>/dev/null
  }

  function is_a_pixelbook() {
    [[ -d /opt/google/cros-containers ]]
    #env | grep -E '(google|cros)' &>/dev/null
  }

  # get data either form stdin or from file
  local buf=
  buf=$(cat "$@")

  local copy_backend_remote_tunnel_port=
  copy_backend_remote_tunnel_port=$(tmux show-option -gvq "@copy_backend_remote_tunnel_port")
  #copy_use_osc52_fallback=$(tmux show-option -gvq "@copy_use_osc52_fallback")
  local copy_use_osc52_fallback=
  copy_use_osc52_fallback="off"


  ## Resolve copy backend: pbcopy (OSX), reattach-to-user-namespace (OSX), xclip/xsel (Linux)
  ## For Pixelbook/Crostini then osc52 is our only option
  local copy_backend=""
  if is_a_pixelbook; then
    copy_backend=""
  elif is_app_installed pbcopy; then
    copy_backend="pbcopy"
  elif is_app_installed reattach-to-user-namespace; then
    copy_backend="reattach-to-user-namespace pbcopy"
  elif [ -n "${DISPLAY-}" ] && is_app_installed xsel; then
    copy_backend="xsel -i --clipboard"
  elif [ -n "${DISPLAY-}" ] && is_app_installed xclip; then
    copy_backend="xclip -i -f -selection primary | xclip -i -selection clipboard"
  elif [ -n "${copy_backend_remote_tunnel_port-}" ] && [ "$(ss -n -4 state listening "( sport = $copy_backend_remote_tunnel_port )" | tail -n +2 | wc -l)" -eq 1 ]; then
    copy_backend="nc localhost $copy_backend_remote_tunnel_port"
  fi

  # if copy backend is resolved, copy and exit
  if [ -n "$copy_backend" ]; then
    cat <<< "$buf" | eval "$copy_backend"
    return 0;
  fi

  # If no copy backends were eligible, decide to fallback to OSC 52 escape sequences
  # Note, most terminals do not handle OSC
  if [ "$copy_use_osc52_fallback" == "off" ]; then
    return 1;
  fi

  # Copy via OSC 52 ANSI escape sequence to controlling terminal
  local buflen=
  buflen=$( cat <<< "$buf" | wc -c )

  # https://sunaku.github.io/tmux-yank-osc52.html
  # The maximum length of an OSC 52 escape sequence is 100_000 bytes, of which
  # 7 bytes are occupied by a "\033]52;c;" header, 1 byte by a "\a" footer, and
  # 99_992 bytes by the base64-encoded result of 74_994 bytes of copyable text
  local maxlen=
  maxlen=74994

  # warn if exceeds maxlen
  if [ "$buflen" -gt "$maxlen" ]; then
    printf "input is %d bytes too long" "$(( buflen - maxlen ))" >&2
  fi

  # build up OSC 52 ANSI escape sequence
  esc="\033]52;c;$( cat <<< "$buf" | head -c $maxlen | base64 | tr -d '\r\n' )\a"
  esc="\033Ptmux;\033$esc\033\\"

  # resolve target terminal to send escape sequence
  # if we are on remote machine, send directly to SSH_TTY to transport escape sequence
  # to terminal on local machine, so data lands in clipboard on our local machine
  local pane_active_tty=
  local target_tty=
  pane_active_tty=$(tmux list-panes -F "#{pane_active} #{pane_tty}" | awk '$1=="1" { print $2 }')
  target_tty="${SSH_TTY:-$pane_active_tty}"

  cat <<< "$esc" > "$target_tty"
}
