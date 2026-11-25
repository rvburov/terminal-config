# Bash 3.2+ prompt. Source this file from an interactive .bashrc.

_terminal_config_directory=${BASH_SOURCE[0]%/*}
if [[ $_terminal_config_directory == "${BASH_SOURCE[0]}" ]]; then
  _terminal_config_directory=.
fi
source "$_terminal_config_directory/git-status.sh"
source "$_terminal_config_directory/files.sh"
unset _terminal_config_directory

# A conservative cell budget keeps wide Unicode names from filling the line.
# ASCII uses one cell; other characters reserve two, including the ellipsis.
_terminal_prompt_width() {
  local value=$1 character
  TERMINAL_PROMPT_WIDTH=0
  while [[ -n $value ]]; do
    character=${value:0:1}
    case $character in
      [\ -~]) TERMINAL_PROMPT_WIDTH=$((TERMINAL_PROMPT_WIDTH + 1)) ;;
      *) TERMINAL_PROMPT_WIDTH=$((TERMINAL_PROMPT_WIDTH + 2)) ;;
    esac
    value=${value:1}
  done
}

_terminal_prompt_fit() {
  local value=$1 budget=$2 character
  _terminal_prompt_width "$value"
  if ((TERMINAL_PROMPT_WIDTH > budget)); then
    if ((budget < 2)); then
      value='.'
      TERMINAL_PROMPT_WIDTH=1
    else
      while ((TERMINAL_PROMPT_WIDTH > budget - 2)); do
        character=${value:0:1}
        case $character in
          [\ -~]) TERMINAL_PROMPT_WIDTH=$((TERMINAL_PROMPT_WIDTH - 1)) ;;
          *) TERMINAL_PROMPT_WIDTH=$((TERMINAL_PROMPT_WIDTH - 2)) ;;
        esac
        value=${value:1}
      done
      value="…$value"
      TERMINAL_PROMPT_WIDTH=$((TERMINAL_PROMPT_WIDTH + 2))
    fi
  fi
  TERMINAL_PROMPT_FITTED=$value
}

terminal_prompt_update() {
  local last_status=$?
  local columns=${COLUMNS:-80}
  local clock='\t'
  local clock_width=8
  local path_budget git_budget branch_budget available user_width state_width host_budget host_width
  local show_user=0 show_host=0 show_git=0
  local reset='\[\e[0m\]'
  local clock_color='\[\e[38;5;250m\]'
  local user_color='\[\e[38;5;114m\]'
  local path_color='\[\e[38;5;81m\]'
  local branch_color='\[\e[38;5;183m\]'
  local status_color='\[\e[38;5;114m\]'
  local separator='\[\e[38;5;242m\] | \[\e[0m\]'
  local marker_color='\[\e[38;5;114m\]'

  if [[ ! $columns =~ ^[0-9]+$ ]]; then
    columns=80
  fi
  columns=$((10#$columns))
  if ((columns < 1)); then
    columns=80
  fi

  TERMINAL_PROMPT_USER=${USER:-${USERNAME:-user}}
  TERMINAL_PROMPT_USER=${TERMINAL_PROMPT_USER//[[:cntrl:]]/?}
  _terminal_prompt_fit "$TERMINAL_PROMPT_USER" 14
  TERMINAL_PROMPT_USER=$TERMINAL_PROMPT_FITTED
  user_width=$TERMINAL_PROMPT_WIDTH
  TERMINAL_PROMPT_HOST=${HOSTNAME:-${COMPUTERNAME:-host}}
  TERMINAL_PROMPT_HOST=${TERMINAL_PROMPT_HOST%%.*}
  TERMINAL_PROMPT_HOST=${TERMINAL_PROMPT_HOST//[[:cntrl:]]/?}
  host_budget=8
  ((columns >= 50)) && host_budget=12
  ((columns >= 100)) && host_budget=18
  _terminal_prompt_fit "$TERMINAL_PROMPT_HOST" "$host_budget"
  TERMINAL_PROMPT_HOST=$TERMINAL_PROMPT_FITTED
  host_width=$TERMINAL_PROMPT_WIDTH
  TERMINAL_PROMPT_PATH=${PWD##*/}
  if [[ $PWD == "$HOME" ]]; then
    TERMINAL_PROMPT_PATH='~'
  elif [[ -z $TERMINAL_PROMPT_PATH ]]; then
    TERMINAL_PROMPT_PATH=/
  fi
  TERMINAL_PROMPT_PATH=${TERMINAL_PROMPT_PATH//[[:cntrl:]]/?}
  TERMINAL_PROMPT_GIT_BRANCH=''
  TERMINAL_PROMPT_GIT_STATE=''

  if terminal_git_status; then
    TERMINAL_PROMPT_GIT_BRANCH=${TERMINAL_GIT_BRANCH//[[:cntrl:]]/?}
    ((TERMINAL_GIT_STAGED > 0)) && TERMINAL_PROMPT_GIT_STATE+=" +$TERMINAL_GIT_STAGED"
    ((TERMINAL_GIT_UNSTAGED > 0)) && TERMINAL_PROMPT_GIT_STATE+=" ~$TERMINAL_GIT_UNSTAGED"
    ((TERMINAL_GIT_UNTRACKED > 0)) && TERMINAL_PROMPT_GIT_STATE+=" ?$TERMINAL_GIT_UNTRACKED"
    ((TERMINAL_GIT_CONFLICTS > 0)) && TERMINAL_PROMPT_GIT_STATE+=" !$TERMINAL_GIT_CONFLICTS"
    ((TERMINAL_GIT_AHEAD > 0)) && TERMINAL_PROMPT_GIT_STATE+=" ↑$TERMINAL_GIT_AHEAD"
    ((TERMINAL_GIT_BEHIND > 0)) && TERMINAL_PROMPT_GIT_STATE+=" ↓$TERMINAL_GIT_BEHIND"
    if [[ -z $TERMINAL_PROMPT_GIT_STATE ]]; then
      TERMINAL_PROMPT_GIT_STATE=' ✓'
    elif ((TERMINAL_GIT_CONFLICTS > 0)); then
      status_color='\[\e[38;5;203m\]'
    elif ((TERMINAL_GIT_STAGED + TERMINAL_GIT_UNSTAGED + TERMINAL_GIT_UNTRACKED > 0)); then
      status_color='\[\e[38;5;221m\]'
    fi
    ((columns >= 60)) && show_git=1
  fi

  if ((columns < 32)); then
    clock='\A'
    clock_width=5
  fi
  ((columns >= 32)) && show_host=1
  ((columns >= 100)) && show_user=1
  available=$((columns - clock_width - 3 - 3 - 6))
  if ((show_host)); then
    available=$((available - host_width - 3))
  fi
  if ((show_user)); then
    available=$((available - user_width - 1))
  fi

  path_budget=$available
  if ((show_git)); then
    git_budget=$((available / 2))
    ((git_budget > 36)) && git_budget=36
    path_budget=$((available - git_budget - 3))
    _terminal_prompt_width "$TERMINAL_PROMPT_GIT_STATE"
    if ((TERMINAL_PROMPT_WIDTH > git_budget - 4)); then
      if ((TERMINAL_GIT_CONFLICTS > 0)); then
        TERMINAL_PROMPT_GIT_STATE=' !'
      elif ((TERMINAL_GIT_STAGED + TERMINAL_GIT_UNSTAGED + TERMINAL_GIT_UNTRACKED > 0)); then
        TERMINAL_PROMPT_GIT_STATE=' *'
      elif ((TERMINAL_GIT_AHEAD + TERMINAL_GIT_BEHIND > 0)); then
        TERMINAL_PROMPT_GIT_STATE=' ↕'
      fi
    fi
    _terminal_prompt_width "$TERMINAL_PROMPT_GIT_STATE"
    state_width=$TERMINAL_PROMPT_WIDTH
    branch_budget=$((git_budget - state_width))
    _terminal_prompt_fit "$TERMINAL_PROMPT_GIT_BRANCH" "$branch_budget"
    TERMINAL_PROMPT_GIT_BRANCH=$TERMINAL_PROMPT_FITTED
  fi

  ((path_budget > 30)) && path_budget=30
  if ((path_budget > 0)); then
    _terminal_prompt_fit "$TERMINAL_PROMPT_PATH" "$path_budget"
    TERMINAL_PROMPT_PATH=$TERMINAL_PROMPT_FITTED
  fi

  PS1="$clock_color$clock$reset"
  if ((show_host)); then
    PS1+="$separator$user_color"
    if ((show_user)); then
      PS1+="\${TERMINAL_PROMPT_USER}@"
    fi
    PS1+="\${TERMINAL_PROMPT_HOST}$reset"
  fi
  if ((path_budget > 0)); then
    PS1+="$separator$path_color\${TERMINAL_PROMPT_PATH}$reset"
  fi
  if ((show_git)); then
    PS1+="$separator$branch_color\${TERMINAL_PROMPT_GIT_BRANCH}$status_color\${TERMINAL_PROMPT_GIT_STATE}$reset"
  fi
  ((last_status != 0)) && marker_color='\[\e[38;5;203m\]'
  if [[ $_terminal_config_input_below == 1 && $- == *i* ]] && ((columns > 8)); then
    # Print the status once as ordinary terminal output. Readline redraws only
    # the short, editable line when the Windows console changes its size.
    local status_format=${PS1//'\['/}
    status_format=${status_format//'\]'/}
    printf '%s\n' "${status_format@P}"
    PS1="$marker_color> $reset"
  elif ((columns <= 8)); then
    PS1="$marker_color> $reset"
  else
    PS1+=" $marker_color> $reset"
  fi
  return "$last_status"
}

shopt -s checkwinsize promptvars
TERMINAL_CONFIG_ACTIVE=1
_terminal_config_input_below=0
if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))); then
  case ${TERMINAL_CONFIG_LAYOUT:-auto} in
    stacked) _terminal_config_input_below=1 ;;
    auto)
      case $OSTYPE in
        msys*|cygwin*)
          if [[ ${TERM_PROGRAM-} == WezTerm || -n ${WEZTERM_PANE-} || -n ${ALACRITTY_WINDOW_ID-} || -n ${ALACRITTY_LOG-} ]]; then
            _terminal_config_input_below=1
          fi ;;
      esac ;;
  esac
fi
if [[ $- == *i* ]]; then
  case ";${PROMPT_COMMAND-};" in
    *';terminal_prompt_update;'*) ;;
    *) PROMPT_COMMAND="terminal_prompt_update${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
  esac
fi
