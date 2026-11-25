#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Использование
  bash install.sh
  bash install.sh --help

Копирует настройки Bash в ${XDG_CONFIG_HOME:-$HOME/.config}/terminal-config
и подключает их из ~/.bashrc. При изменении существующего файла сохраняет копию.
EOF
}

for argument in "$@"; do
    case "$argument" in
        --help|-h) usage; exit 0 ;;
        *) printf 'Неизвестный аргумент %s\n' "$argument" >&2; usage >&2; exit 1 ;;
    esac
done

if [ -z "${HOME:-}" ]; then
    printf 'Переменная HOME должна указывать на домашний каталог.\n' >&2
    exit 1
fi

project_directory=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
configuration_directory="${XDG_CONFIG_HOME:-$HOME/.config}/terminal-config"
for script_name in prompt.sh files.sh git-status.sh; do
    source_file="$project_directory/shell/$script_name"
    if [ ! -f "$source_file" ]; then
        printf 'Не найден файл %s\n' "$source_file" >&2
        exit 1
    fi
    if ! "$BASH" -n "$source_file"; then
        printf 'Ошибка синтаксиса в %s\n' "$source_file" >&2
        exit 1
    fi
done

prepared_file=''
bashrc_prepared=''
profile_prepared=''
cleanup() {
    local temporary_file
    for temporary_file in "$prepared_file" "$bashrc_prepared" "$profile_prepared"; do
        if [ -n "$temporary_file" ] && [ -f "$temporary_file" ]; then
            rm -f -- "$temporary_file"
        fi
    done
}
trap cleanup EXIT

prepare_file() {
    prepared_file=$(mktemp "${1}.terminal-config.XXXXXX")
    if [ -e "$1" ]; then
        cp -pL -- "$1" "$prepared_file"
    fi
}

write_if_changed() {
    local destination=$1 backup suffix
    if [ -f "$destination" ] && cmp -s -- "$destination" "$prepared_file"; then
        rm -f -- "$prepared_file"
        prepared_file=''
        return
    fi
    if [ -e "$destination" ]; then
        backup="${destination}.bak.$(date '+%Y%m%d-%H%M%S')"
        suffix=1
        while [ -e "$backup" ] || [ -L "$backup" ]; do
            backup="${destination}.bak.$(date '+%Y%m%d-%H%M%S').${suffix}"
            suffix=$((suffix + 1))
        done
        cp -pL -- "$destination" "$backup"
    fi
    if [ -L "$destination" ]; then
        cat -- "$prepared_file" > "$destination"
        rm -f -- "$prepared_file"
    else
        mv -f -- "$prepared_file" "$destination"
    fi
    prepared_file=''
    printf 'Обновлён %s\n' "$destination"
}

# Меняется только фактическая команда source или . с первым аргументом OMB.
rewrite_startup_file() {
    local source=$1 block=$2
    awk -v block="$block" '
        function loads_oh_my_bash(line, rest, argument, quote, escaped, i, character, suffix) {
            if (line !~ /^[[:space:]]*(source|\.)[[:space:]]+/) return 0
            rest = line
            sub(/^[[:space:]]*(source|\.)[[:space:]]+/, "", rest)
            argument = ""
            quote = ""
            escaped = 0
            for (i = 1; i <= length(rest); i++) {
                character = substr(rest, i, 1)
                if (escaped) {
                    argument = argument character
                    escaped = 0
                } else if (character == "\\" && quote != "\047") {
                    escaped = 1
                } else if (quote != "") {
                    if (character == quote) quote = ""
                    else argument = argument character
                } else if (character == "\"" || character == "\047") {
                    quote = character
                } else if (character ~ /[[:space:];&|<>()]/ || (character == "#" && argument == "")) {
                    break
                } else {
                    argument = argument character
                }
            }
            if (argument !~ /(^|\/)oh-my-bash[.]sh$/) return 0
            suffix = substr(rest, i)
            sub(/^[[:space:]]+/, "", suffix)
            if (quote != "" || escaped || (suffix != "" && substr(suffix, 1, 1) != "#")) return 2
            return 1
        }
        {
            marker = $0
            sub(/\r$/, "", marker)
            if (marker == "# >>> terminal-config " block " >>>") {
                if (inside) exit 2
                inside = 1
                next
            }
            if (marker == "# <<< terminal-config " block " <<<") {
                if (!inside) exit 2
                inside = 0
                next
            }
            if (inside) next
            source_kind = loads_oh_my_bash($0)
            if (source_kind == 2) {
                printf "Не могу безопасно изменить сложную строку %d в %s. Разнесите source oh-my-bash.sh и остальные команды на отдельные строки.\n", NR, FILENAME > "/dev/stderr"
                exit 3
            }
            if (source_kind == 1) {
                match($0, /^[[:space:]]*/)
                print substr($0, 1, RLENGTH) ": # terminal-config disabled oh-my-bash: " $0
            } else print $0
        }
        END { if (inside) exit 2 }
    ' "$source"
}

mkdir -p -- "$configuration_directory"
configuration_directory=$(CDPATH= cd -- "$configuration_directory" && pwd -P)

# Оба startup-файла сначала готовятся и проверяются, затем применяются вместе.
bashrc="$HOME/.bashrc"
prepare_file "$bashrc"
startup_source=/dev/null
[ ! -e "$bashrc" ] || startup_source=$bashrc
rewrite_startup_file "$startup_source" bashrc > "$prepared_file"
{
    printf '%s\n' '# >>> terminal-config bashrc >>>'
    printf '%s\n' '_TERMINAL_CONFIG_BASHRC_LOADED=1'
    printf 'if [ -r %q ]; then\n' "$configuration_directory/prompt.sh"
    printf '    . %q\n' "$configuration_directory/prompt.sh"
    printf '%s\n' 'fi' '# <<< terminal-config bashrc <<<'
} >> "$prepared_file"
if ! "$BASH" -n "$prepared_file"; then
    printf 'Ошибка синтаксиса в подготовленном %s. Исходные startup-файлы сохранены.\n' "$bashrc" >&2
    exit 1
fi
bashrc_prepared=$prepared_file
prepared_file=''

profile="$HOME/.bash_profile"
prepare_file "$profile"
if [ -e "$profile" ]; then
    rewrite_startup_file "$profile" login > "$prepared_file"
else
    # Bash обычно выбирает первый существующий login-файл. Сохраняем этот порядок.
    cat > "$prepared_file" <<'EOF'
if [ -r "$HOME/.bash_login" ]; then
    . "$HOME/.bash_login"
elif [ -r "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi
EOF
fi
cat >> "$prepared_file" <<'EOF'
# >>> terminal-config login >>>
if [ "${_TERMINAL_CONFIG_BASHRC_LOADED:-}" != 1 ] && [ -r "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
# <<< terminal-config login <<<
EOF
if ! "$BASH" -n "$prepared_file"; then
    printf 'Ошибка синтаксиса в подготовленном %s. Исходные startup-файлы сохранены.\n' "$profile" >&2
    exit 1
fi
profile_prepared=$prepared_file
prepared_file=''

for source_file in "$project_directory"/shell/*.sh; do
    [ -f "$source_file" ] || continue
    destination="$configuration_directory/${source_file##*/}"
    prepare_file "$destination"
    cat -- "$source_file" > "$prepared_file"
    write_if_changed "$destination"
done

prepared_file=$bashrc_prepared
write_if_changed "$bashrc"
bashrc_prepared=''
prepared_file=$profile_prepared
write_if_changed "$profile"
profile_prepared=''

printf 'Настройки установлены в %s\n' "$configuration_directory"
printf 'Откройте новый терминал, чтобы применить настройки.\n'
printf 'Для иконок выберите Nerd Font в настройках терминала на клиентском устройстве.\n'
