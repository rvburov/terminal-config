#!/usr/bin/env bash
# Portable Bash tests. Real PS1 expansion requires Bash 4.4+; the configuration
# itself and the remaining assertions use only Bash 3.2 features.

test_directory=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
project_directory=${test_directory%/*}
test_base=$(cd "${TMPDIR:-/tmp}" && pwd -P) || exit 1
test_temp=$(mktemp -d "$test_base/terminal-prompt-test.XXXXXX") || exit 1
cleanup() {
  case "$test_temp" in
    "$test_base"/terminal-prompt-test.??????) rm -rf -- "$test_temp" ;;
    *) printf 'Refusing to clean unexpected fixture path: %s\n' "$test_temp" >&2 ;;
  esac
}
trap cleanup EXIT
failures=0
checks=0

check() {
  checks=$((checks + 1))
  if ! "$@"; then
    printf 'FAIL: %s\n' "$*" >&2
    failures=$((failures + 1))
  fi
}

equal() { [[ $1 == "$2" ]]; }
contains() { [[ $1 == *"$2"* ]]; }
absent() { [[ $1 != *"$2"* ]]; }
missing() { [[ ! -e $1 ]]; }
smaller_than() { (( $1 < $2 )); }
source "$project_directory/shell/prompt.sh"

check equal "$TERMINAL_CONFIG_ACTIVE" 1

# No real repository operations are needed for prompt layout/status coverage.
mock_repo=0
mock_branch=main
mock_staged=0
mock_unstaged=0
mock_untracked=0
mock_conflicts=0
mock_ahead=0
mock_behind=0
terminal_git_status() {
  TERMINAL_GIT_BRANCH=$mock_branch
  TERMINAL_GIT_STAGED=$mock_staged
  TERMINAL_GIT_UNSTAGED=$mock_unstaged
  TERMINAL_GIT_UNTRACKED=$mock_untracked
  TERMINAL_GIT_CONFLICTS=$mock_conflicts
  TERMINAL_GIT_AHEAD=$mock_ahead
  TERMINAL_GIT_BEHIND=$mock_behind
  ((mock_repo))
}

# \[ and \] must enclose each complete nonprinting SGR sequence. Any color
# outside those markers corrupts Readline's cursor position after a resize.
check_markers() {
  local rest=$PS1
  local sgr='\\\[\\e\[[0-9;]*m\\\]'
  while [[ $rest =~ $sgr ]]; do
    rest=${rest/"${BASH_REMATCH[0]}"/}
  done
  check absent "$rest" '\['
  check absent "$rest" '\]'
  check absent "$rest" '\e['
  check absent "$rest" '\e'
  check absent "$rest" $'\033'
  check absent "$PS1" $'\n'
  check absent "$PS1" $'\r'
}

can_expand=0
if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))); then
  can_expand=1
fi

render_prompt() {
  # Kept in a function so older Bash does not evaluate the newer expansion.
  rendered=${PS1@P}
  rendered=${rendered//$'\001'/}
  rendered=${rendered//$'\002'/}
  local sgr=$'\033''\[[0-9;]*m'
  while [[ $rendered =~ $sgr ]]; do
    rendered=${rendered/"${BASH_REMATCH[0]}"/}
  done
}

cell_width() {
  # The wide fixtures deliberately use these two known two-cell characters;
  # other text in the fixture is Latin/Cyrillic and one-cell punctuation.
  local rest=$1 char
  cells=0
  while [[ -n $rest ]]; do
    char=${rest:0:1}
    rest=${rest:1}
    case $char in
      界|🧪) cells=$((cells + 2)) ;;
      *) cells=$((cells + 1)) ;;
    esac
  done
}

USER='long-user-name-for-width'
HOSTNAME='long-host-name-for-width.example.test'
HOME=/home/test
long_path='very-long-project-name-with-several-segments'
long_branch='feature/very-long-branch-name-with-several-segments'
for mock_repo in 0 1; do
  for COLUMNS in 120 100 99 80 60 59 50 49 40 35 32 31 25 16 9 8; do
    PWD="/work/$long_path"
    mock_branch=$long_branch
    terminal_prompt_update
    check_markers
    if ((COLUMNS >= 32)); then
      check contains "$PS1" '\t'
    elif ((COLUMNS >= 9)); then
      check contains "$PS1" '\A'
    else
      check absent "$PS1" '\A'
      check absent "$PS1" '\t'
    fi
    if ((COLUMNS >= 32)); then
      check contains "$PS1" '${TERMINAL_PROMPT_HOST}'
      check absent "$TERMINAL_PROMPT_HOST" '.example'
      host_budget=8
      ((COLUMNS >= 50)) && host_budget=12
      ((COLUMNS >= 100)) && host_budget=18
      cell_width "$TERMINAL_PROMPT_HOST"
      check smaller_than "$cells" "$((host_budget + 1))"
    else
      check absent "$PS1" '${TERMINAL_PROMPT_HOST}'
    fi
    if ((COLUMNS >= 100)); then
      check contains "$PS1" '${TERMINAL_PROMPT_USER}@${TERMINAL_PROMPT_HOST}'
    else
      check absent "$PS1" '${TERMINAL_PROMPT_USER}'
    fi
    if ((can_expand)); then
      render_prompt
      cell_width "$rendered"
      if ((cells >= COLUMNS)); then
        printf 'Layout: repo=%s columns=%s cells=%s prompt=%q\n' \
          "$mock_repo" "$COLUMNS" "$cells" "$rendered" >&2
      fi
      # Leave room for input rather than landing on the automatic wrap column.
      check smaller_than "$cells" "$COLUMNS"
    fi
    if ((mock_repo && COLUMNS >= 60)); then
      check contains "$PS1" '${TERMINAL_PROMPT_GIT_BRANCH}'
    else
      check absent "$PS1" '${TERMINAL_PROMPT_GIT_BRANCH}'
    fi
  done
done

# Use the short hostname, then the platform fallback, then a stable default.
COLUMNS=120
mock_repo=0
USER=user
PWD=/work/project
HOSTNAME=workstation.example.test
terminal_prompt_update
check equal "$TERMINAL_PROMPT_HOST" workstation
if ((can_expand)); then
  render_prompt
  check contains "$rendered" 'user@workstation'
fi
HOSTNAME=''
COMPUTERNAME=desktop.example.test
terminal_prompt_update
check equal "$TERMINAL_PROMPT_HOST" desktop
COMPUTERNAME=''
terminal_prompt_update
check equal "$TERMINAL_PROMPT_HOST" host
HOSTNAME='long-host-name-for-width.example.test'

COLUMNS=120
mock_repo=1
mock_branch=main
mock_staged=2
mock_unstaged=3
mock_untracked=4
mock_conflicts=1
mock_ahead=5
mock_behind=6
terminal_prompt_update
check equal "$TERMINAL_PROMPT_GIT_STATE" ' +2 ~3 ?4 !1 ↑5 ↓6'
check contains "$PS1" '\e[38;5;203m'
mock_conflicts=0
terminal_prompt_update
check contains "$PS1" '\e[38;5;221m'
mock_staged=999999
mock_unstaged=999999
mock_untracked=999999
mock_conflicts=999999
mock_ahead=999999
mock_behind=999999
for COLUMNS in 120 80 60 59 50 40; do
  terminal_prompt_update
  check contains "$TERMINAL_PROMPT_GIT_STATE" '!'
  if ((can_expand)); then
    render_prompt
    cell_width "$rendered"
    check smaller_than "$cells" "$COLUMNS"
  fi
done
COLUMNS=120
mock_staged=0
mock_unstaged=0
mock_untracked=0
mock_conflicts=0
mock_ahead=0
mock_behind=0
terminal_prompt_update
check equal "$TERMINAL_PROMPT_GIT_STATE" ' ✓'
mock_repo=0
terminal_prompt_update
check equal "$TERMINAL_PROMPT_GIT_BRANCH" ''
check equal "$TERMINAL_PROMPT_GIT_STATE" ''

# The update must return the command's status, not the result of git/formatting.
for mock_repo in 0 1; do
  for previous_status in 0 1 2 127; do
    (exit "$previous_status")
    terminal_prompt_update
    observed_status=$?
    check equal "$observed_status" "$previous_status"
    if ((previous_status)); then
      check contains "$PS1" ' \[\e[38;5;203m\]> '
    else
      check contains "$PS1" ' \[\e[38;5;114m\]> '
    fi
  done
done

# Invalid dimensions must not be treated as arithmetic expressions or commands.
cd "$test_temp" || exit 1
for COLUMNS in invalid 0 -1 '$(>pwn-columns)' 0080; do
  terminal_prompt_update
  check contains "$PS1" '> '
done

# Prompt expansion must never interpret path, user, host, or branch text as shell
# code. Keep the sentinel names relative, avoiding slash/basename ambiguity.
COLUMNS=120
mock_repo=1
USER='$(>pwn-user)'
HOSTNAME='$(>pwn-host).example'
PWD='/work/$(>pwn-path)'
mock_branch='$(>pwn-branch)'
terminal_prompt_update
check contains "$PS1" '${TERMINAL_PROMPT_USER}'
check contains "$PS1" '${TERMINAL_PROMPT_HOST}'
check contains "$PS1" '${TERMINAL_PROMPT_PATH}'
check contains "$PS1" '${TERMINAL_PROMPT_GIT_BRANCH}'
if ((can_expand)); then
  render_prompt
  check contains "$rendered" '$(>pwn-user)'
  check contains "$rendered" '$(>pwn-host)'
  check contains "$rendered" '$(>pwn-path)'
  check contains "$rendered" '$(>pwn-branch)'
fi
check missing "$test_temp/pwn-user"
check missing "$test_temp/pwn-host"
check missing "$test_temp/pwn-path"
check missing "$test_temp/pwn-branch"
PWD='/work/`>pwn-path-tick`'
HOSTNAME='`>pwn-host-tick`.example'
mock_branch='`>pwn-branch-tick`'
terminal_prompt_update
if ((can_expand)); then
  render_prompt
  check contains "$rendered" '`>pwn-path-tick`'
  check contains "$rendered" '`>pwn-host-tick`'
  check contains "$rendered" '`>pwn-branch-tick`'
fi
check missing "$test_temp/pwn-path-tick"
check missing "$test_temp/pwn-host-tick"
check missing "$test_temp/pwn-branch-tick"
check missing "$test_temp/pwn-columns"

# Terminal control characters supplied through names cannot move the cursor.
PWD=$'/work/folder\033[2J\nname'
mock_branch=$'branch\r\033[2J'
USER=$'user\nname'
HOSTNAME=$'host\033[2J\nname\rcode\tbell\aend\177'
terminal_prompt_update
check absent "$TERMINAL_PROMPT_PATH" $'\033'
check absent "$TERMINAL_PROMPT_PATH" $'\n'
check absent "$TERMINAL_PROMPT_GIT_BRANCH" $'\r'
check absent "$TERMINAL_PROMPT_GIT_BRANCH" $'\033'
check absent "$TERMINAL_PROMPT_USER" $'\n'
check absent "$TERMINAL_PROMPT_HOST" $'\033'
check absent "$TERMINAL_PROMPT_HOST" $'\n'
check absent "$TERMINAL_PROMPT_HOST" $'\r'
check absent "$TERMINAL_PROMPT_HOST" $'\t'
check absent "$TERMINAL_PROMPT_HOST" $'\a'
check absent "$TERMINAL_PROMPT_HOST" $'\177'

# Names with wide glyphs must fit by terminal cells, not string length.
if ((can_expand)); then
  for wide_name in \
    '界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界界' \
    '🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪🧪'; do
    USER=$wide_name
    HOSTNAME="$wide_name.example"
    for COLUMNS in 120 100 99 80 60 59 50 49 40 35 32 31 25 16 9 8; do
      PWD="/work/$wide_name"
      mock_branch=$wide_name
      terminal_prompt_update
      render_prompt
      cell_width "$rendered"
      if ((cells >= COLUMNS)); then
        printf 'Wide layout: columns=%s cells=%s prompt=%q\n' \
          "$COLUMNS" "$cells" "$rendered" >&2
      fi
      check smaller_than "$cells" "$COLUMNS"
      if ((COLUMNS >= 32)); then
        host_budget=8
        ((COLUMNS >= 50)) && host_budget=12
        ((COLUMNS >= 100)) && host_budget=18
        cell_width "$TERMINAL_PROMPT_HOST"
        check smaller_than "$cells" "$((host_budget + 1))"
      fi
    done
  done
fi

# Registration is interactive-only, survives an existing hook, and is
# idempotent when .bashrc or this module is sourced again.
interactive_result=$("$BASH" --noprofile --norc -i -c '
  PROMPT_COMMAND=": preserved_hook"
  source "$1/shell/prompt.sh"
  source "$1/shell/prompt.sh"
  printf "%s" "$PROMPT_COMMAND"
' prompt-test "$project_directory" 2>/dev/null)
check equal "$interactive_result" 'terminal_prompt_update; : preserved_hook'
check equal "${PROMPT_COMMAND-}" ''
source "$project_directory/shell/prompt.sh"
check equal "${PROMPT_COMMAND-}" ''
check equal "$TERMINAL_CONFIG_ACTIVE" 1

# The stacked layout prints one context line and leaves only a short editable
# prompt. Exercise actual interactive/@P expansion, including hostile names.
if ((can_expand)); then
  mkdir "$test_temp/stacked"
  "$BASH" --noprofile --norc -i -c '
    cd "$2" || exit 1
    trap ": preserved_winch_handler" WINCH
    trap -p WINCH > trap-before.txt
    TERMINAL_CONFIG_LAYOUT=stacked
    source "$1/shell/prompt.sh"
    source "$1/shell/prompt.sh"
    COLUMNS=200
    USER='\''$(>s-user)'\''
    HOSTNAME='\''$(>s-host).example'\''
    PWD='\''/work/$(>s-path)_`>s-tick`'\''
    terminal_git_status() {
      TERMINAL_GIT_BRANCH='\''$(>s-git)'\''
      TERMINAL_GIT_STAGED=0 TERMINAL_GIT_UNSTAGED=0 TERMINAL_GIT_UNTRACKED=0
      TERMINAL_GIT_CONFLICTS=0 TERMINAL_GIT_AHEAD=0 TERMINAL_GIT_BEHIND=0
      return 0
    }
    (exit 17)
    terminal_prompt_update > context.txt
    printf "%s" "$?" > update-status.txt
    printf "%s" "$PS1" > ps1-raw.txt
    printf "%s" "${PS1@P}" > ps1-rendered.txt
    trap -p WINCH > trap-after.txt
  ' stacked-test "$project_directory" "$test_temp/stacked" 2> "$test_temp/stacked/stderr.txt"
  check equal "$?" 0
  check equal "$(cat "$test_temp/stacked/update-status.txt")" 17
  check cmp -s "$test_temp/stacked/trap-before.txt" "$test_temp/stacked/trap-after.txt"
  check contains "$(cat "$test_temp/stacked/trap-after.txt")" 'preserved_winch_handler'
  stacked_context=$(cat "$test_temp/stacked/context.txt")
  check equal "$(wc -l < "$test_temp/stacked/context.txt")" 1
  check contains "$stacked_context" '$(>s-user)'
  check contains "$stacked_context" '$(>s-host)'
  check contains "$stacked_context" '$(>s-path)_`>s-tick`'
  check contains "$stacked_context" '$(>s-git)'
  check absent "$stacked_context" $'\001'
  check absent "$stacked_context" $'\002'
  check contains "$(cat "$test_temp/stacked/ps1-raw.txt")" '\[\e[38;5;203m\]> '
  stacked_prompt=$(cat "$test_temp/stacked/ps1-rendered.txt")
  stacked_prompt=${stacked_prompt//$'\001'/}
  stacked_prompt=${stacked_prompt//$'\002'/}
  stacked_sgr=$'\033''\[[0-9;]*m'
  while [[ $stacked_prompt =~ $stacked_sgr ]]; do
    stacked_prompt=${stacked_prompt/"${BASH_REMATCH[0]}"/}
  done
  check equal "$stacked_prompt" '> '
  for stacked_sentinel in s-user s-host s-path s-tick s-git; do
    check missing "$test_temp/stacked/$stacked_sentinel"
  done
fi

if ((!can_expand)); then
  printf 'SKIP: real PS1 expansion needs Bash 4.4+ (running %s).\n' "$BASH_VERSION"
fi
printf 'Prompt: %s checks, %s failures.\n' "$checks" "$failures"
((failures == 0))
