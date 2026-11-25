# Bash 3.2+ file tree. Per-entry work uses shell builtins only.
_terminal_files_name() {
  local name=$1
  name=${name//\\/\\\\}
  name=${name//$'\n'/\\n}
  name=${name//$'\r'/\\r}
  name=${name//$'\t'/\\t}
  name=${name//$'\e'/\\e}
  name=${name//[[:cntrl:]]/?}
  printf '%s' "$name"
}

_terminal_files_style() {
  local path=$1 name=${1##*/}
  _terminal_files_icon=''
  _terminal_files_color=252
  if [[ -L $path ]]; then
    _terminal_files_icon=''; _terminal_files_color=117
  elif [[ -d $path ]]; then
    _terminal_files_icon=''; _terminal_files_color=81
  elif [[ -f $path && -x $path ]]; then
    _terminal_files_icon=''; _terminal_files_color=114
  else
    case "$name" in
      *.[mM][dD]) _terminal_files_icon=''; _terminal_files_color=229 ;;
      *.[sS][hH]|*.[bB][aA][sS][hH]) _terminal_files_icon=''; _terminal_files_color=114 ;;
      *.[jJ][sS][oO][nN]|*.[yY][aA][mM][lL]|*.[yY][mM][lL]|*.[tT][oO][mM][lL]|*.[iI][nN][iI]|*.[cC][oO][nN][fF][iI][gG])
        _terminal_files_icon=''; _terminal_files_color=115 ;;
      *.[zZ][iI][pP]|*.[tT][aA][rR]|*.[gG][zZ]|*.[bB][zZ]2|*.[xX][zZ]|*.7[zZ]|*.[rR][aA][rR])
        _terminal_files_icon=''; _terminal_files_color=215 ;;
      *.[pP][nN][gG]|*.[jJ][pP][gG]|*.[jJ][pP][eE][gG]|*.[gG][iI][fF]|*.[sS][vV][gG]|*.[wW][eE][bB][pP])
        _terminal_files_icon=''; _terminal_files_color=177 ;;
      *.[pP][dD][fF]) _terminal_files_icon=''; _terminal_files_color=183 ;;
      *.[dD][oO][cC]|*.[dD][oO][cC][xX]) _terminal_files_icon=''; _terminal_files_color=183 ;;
      *.[xX][lL][sS]|*.[xX][lL][sS][xX]) _terminal_files_icon=''; _terminal_files_color=114 ;;
    esac
  fi
}

_terminal_files_print() {
  local path=$1 label=$2
  _terminal_files_style "$path"
  if ((_terminal_files_use_color)); then printf '\033[38;5;%sm' "$_terminal_files_color"; fi
  printf '%s ' "$_terminal_files_icon"
  _terminal_files_name "$label"
  if [[ -d $path && ! -L $path && $label != */ ]]; then printf '/'; fi
  if ((_terminal_files_use_color)); then printf '\033[0m'; fi
  printf '\n'
}

_terminal_files_extension_key() {
  local name=$1 extension='' character prefix
  local uppercase=ABCDEFGHIJKLMNOPQRSTUVWXYZ lowercase=abcdefghijklmnopqrstuvwxyz
  local LC_ALL=C
  _terminal_files_extension=''
  while [[ $name == .* ]]; do name=${name#.}; done
  if [[ $name == *.* ]]; then extension=${name##*.}; fi
  while [[ -n $extension ]]; do
    character=${extension:0:1}
    case "$character" in
      [A-Z])
        prefix=${uppercase%%"$character"*}
        character=${lowercase:${#prefix}:1}
        ;;
    esac
    _terminal_files_extension+=$character
    extension=${extension:1}
  done
}

# Stable bottom-up merge sort. These two arrays belong to the calling walker.
# Equal extension keys retain the filename order supplied by the shell glob.
_terminal_files_sort() {
  local count=$1 width left middle right first second target index
  local LC_ALL=C
  local -a sorted_files sorted_keys
  for ((width = 1; width < count; width *= 2)); do
    for ((left = 0; left < count; left += width * 2)); do
      middle=$((left + width))
      right=$((left + width * 2))
      if ((middle > count)); then middle=$count; fi
      if ((right > count)); then right=$count; fi
      first=$left
      second=$middle
      for ((target = left; target < right; target++)); do
        if ((second < right)) &&
          { ((first >= middle)) || [[ ${file_keys[first]} > ${file_keys[second]} ]]; }; then
          sorted_files[target]=${files[second]}
          sorted_keys[target]=${file_keys[second]}
          second=$((second + 1))
        else
          sorted_files[target]=${files[first]}
          sorted_keys[target]=${file_keys[first]}
          first=$((first + 1))
        fi
      done
    done
    for ((index = 0; index < count; index++)); do
      files[index]=${sorted_files[index]}
      file_keys[index]=${sorted_keys[index]}
    done
  done
}

_terminal_files_walk() {
  local directory=$1 prefix=$2 depth=$3
  local path name index directory_count=0 file_count=0 result=0 next_prefix
  local _terminal_files_extension=''
  local -a directories files file_keys
  directories=()
  files=()
  if ((depth >= _terminal_files_level)); then return 0; fi
  if [[ ! -r $directory || ! -x $directory ]]; then
    printf 'terminal-config — нет доступа к каталогу ' >&2
    _terminal_files_name "$directory" >&2
    printf '\n' >&2
    return 1
  fi
  for path in "$directory"/*; do
    name=${path##*/}
    [[ $name == . || $name == .. ]] && continue
    if ((!_terminal_files_show_hidden)) && [[ $name == .* ]]; then continue; fi
    if [[ -d $path && ! -L $path ]]; then
      directories[directory_count]=$path
      directory_count=$((directory_count + 1))
    else
      _terminal_files_extension_key "$name"
      files[file_count]=$path
      file_keys[file_count]=$_terminal_files_extension
      file_count=$((file_count + 1))
    fi
  done
  _terminal_files_sort "$file_count"
  for ((index = 0; index < file_count; index++)); do
    directories[directory_count]=${files[index]}
    directory_count=$((directory_count + 1))
  done
  for ((index = 0; index < directory_count; index++)); do
    path=${directories[index]}
    name=${path##*/}
    if ((index + 1 == directory_count)); then
      printf '%s└── ' "$prefix"
      next_prefix="$prefix    "
    else
      printf '%s├── ' "$prefix"
      next_prefix="$prefix│   "
    fi
    _terminal_files_print "$path" "$name"
    if [[ -d $path && ! -L $path ]]; then
      _terminal_files_walk "$path" "$next_prefix" "$((depth + 1))" || result=1
    fi
  done
  return "$result"
}

_terminal_files_help() {
  printf '%s\n' \
    'ls [-a|-A] [--level=N] [--color=auto|always|never] [--] [пути...]' \
    'tree — те же опции, глубина по умолчанию 3, для ls — 1.' \
    '--level от 0 до 64. Значение 0 показывает только корень. -a/-A показывают скрытые элементы, кроме . и ..' \
    'Символические ссылки не раскрываются. Другие опции (-l, -la и прочие) передаются системному ls.'
}

_terminal_files_main() (
  local _terminal_files_level=$1
  local _terminal_files_show_hidden=0 _terminal_files_use_color=0
  local _terminal_files_icon='' _terminal_files_color=252
  local parse_options=1 color_mode=auto level_text path index path_count=0 result=0
  local -a original_arguments paths
  shift
  original_arguments=("$@")
  paths=()
  while (($#)); do
    if ((parse_options)); then
      case "$1" in
        --) parse_options=0 ;;
        --help) _terminal_files_help; return 0 ;;
        -a|-A) _terminal_files_show_hidden=1 ;;
        --level=*)
          level_text=${1#--level=}
          case "$level_text" in
            ''|*[!0-9]*) printf 'terminal-config — --level требует целое число от 0\n' >&2; return 2 ;;
          esac
          if ((${#level_text} > 3)); then
            printf 'terminal-config — --level допускает значения от 0 до 64\n' >&2
            return 2
          fi
          _terminal_files_level=$((10#$level_text))
          if ((_terminal_files_level > 64)); then
            printf 'terminal-config — --level допускает значения от 0 до 64\n' >&2
            return 2
          fi
          ;;
        --color=*)
          color_mode=${1#--color=}
          case "$color_mode" in
            auto|always|never) ;;
            *) printf 'terminal-config — допустимые цвета auto, always, never\n' >&2; return 2 ;;
          esac
          ;;
        -*) command ls "${original_arguments[@]}"; return "$?" ;;
        *) paths[path_count]=$1; path_count=$((path_count + 1)) ;;
      esac
    else
      paths[path_count]=$1
      path_count=$((path_count + 1))
    fi
    shift
  done
  if ((path_count == 0)); then paths[0]=.; path_count=1; fi
  if [[ $color_mode == always ]] || { [[ $color_mode == auto ]] && [[ -t 1 ]]; }; then
    _terminal_files_use_color=1
  fi
  # These glob settings belong only to this subshell.
  unset GLOBIGNORE
  set +f
  shopt -s nullglob dotglob
  shopt -u failglob nocaseglob
  for ((index = 0; index < path_count; index++)); do
    path=${paths[index]}
    if ((index)); then printf '\n'; fi
    if [[ ! -e $path && ! -L $path ]]; then
      printf 'terminal-config — путь не существует ' >&2
      _terminal_files_name "$path" >&2
      printf '\n' >&2
      result=1
      continue
    fi
    _terminal_files_print "$path" "$path"
    if [[ -d $path && ! -L $path ]]; then
      _terminal_files_walk "$path" '' 0 || result=1
    fi
  done
  return "$result"
)

terminal_ls() {
  _terminal_files_main 1 "$@"
}

terminal_tree() {
  _terminal_files_main 3 "$@"
}

alias ls='terminal_ls'
alias tree='terminal_tree'
