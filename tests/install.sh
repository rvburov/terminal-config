#!/usr/bin/env bash
set -euo pipefail

project_directory=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_parent=${TMPDIR:-/tmp}
temporary_parent=$(CDPATH= cd -- "$temporary_parent" && pwd -P)
test_directory=$(mktemp -d "$temporary_parent/terminal-config-tests.XXXXXX")
cleanup() {
    case "$test_directory" in
        "$temporary_parent"/terminal-config-tests.*) rm -rf -- "$test_directory" ;;
        *) printf 'Небезопасный путь очистки %s\n' "$test_directory" >&2 ;;
    esac
}
trap cleanup EXIT

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

fixture_project="$test_directory/project with spaces"
mkdir -p -- "$fixture_project/shell"
cp -- "$project_directory/install.sh" "$fixture_project/install.sh"
cat > "$fixture_project/shell/prompt.sh" <<'EOF'
TERMINAL_TEST_LOAD_COUNT=$(( ${TERMINAL_TEST_LOAD_COUNT:-0} + 1 ))
EOF
printf ':\n' > "$fixture_project/shell/files.sh"
printf ':\n' > "$fixture_project/shell/git-status.sh"

run_installer() {
    HOME="$case_home" XDG_CONFIG_HOME="$case_configuration" \
        bash "$fixture_project/install.sh" "$@" > "$case_home/install-output.txt"
}

check_login() {
    HOME="$case_home" XDG_CONFIG_HOME="$case_configuration" \
        bash --login -c '
            [ "${TERMINAL_TEST_LOAD_COUNT:-0}" -eq 1 ] &&
            [ "${TERMINAL_TEST_PROFILE:-}" = preserved ]
        ' || fail 'login Bash не сохранил профиль или не загрузил prompt ровно один раз'
}

case_home="$test_directory/existing profile home"
case_configuration="$case_home/config with spaces"
mkdir -p -- "$case_home"
cat > "$case_home/.bashrc" <<'EOF'
export TERMINAL_TEST_USER_LINE=preserved
# source "$HOME/oh-my-bash.sh"
printf '%s\n' 'source oh-my-bash.sh is mentioned here' > /dev/null
if [ -f "$HOME/oh-my-bash.sh" ]; then
    source "$HOME/oh-my-bash.sh"
fi
. "$HOME"/oh-my-bash.sh
source "$HOME/custom.sh" # oh-my-bash.sh is only a comment
# user trailing line
EOF
cat > "$case_home/.bash_profile" <<'EOF'
export TERMINAL_TEST_PROFILE=preserved
if [ -f "$HOME/oh-my-bash.sh" ]; then
    source "$HOME/oh-my-bash.sh"
fi
if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi
EOF
printf 'export TERMINAL_TEST_CUSTOM=preserved\n' > "$case_home/custom.sh"
printf 'printf invoked >> "$HOME/omb-was-sourced"\n' > "$case_home/oh-my-bash.sh"
cp -- "$case_home/.bashrc" "$case_home/original-bashrc"
cp -- "$case_home/.bash_profile" "$case_home/original-profile"
run_installer

for name in prompt.sh files.sh git-status.sh; do
    cmp -s -- "$fixture_project/shell/$name" "$case_configuration/terminal-config/$name" || fail "Не скопирован $name"
done
grep -qF ': # terminal-config disabled oh-my-bash:' "$case_home/.bashrc" || fail 'source OMB не заменён на no-op'
grep -qF ': # terminal-config disabled oh-my-bash: . "$HOME"/oh-my-bash.sh' "$case_home/.bashrc" || fail 'Точка OMB не отключена'
bash -n "$case_home/.bashrc" || fail 'Нарушен синтаксис .bashrc'
bash -n "$case_home/.bash_profile" || fail 'Нарушен синтаксис .bash_profile'
grep -qF 'source "$HOME/custom.sh" # oh-my-bash.sh is only a comment' "$case_home/.bashrc" || fail 'Изменена пользовательская команда source'
grep -qF '# user trailing line' "$case_home/.bashrc" || fail 'Потерян пользовательский текст'
grep -qF '# source "$HOME/oh-my-bash.sh"' "$case_home/.bashrc" || fail 'Изменён исходный комментарий'
[ "$(find "$case_home" -name '*.bak.*' -type f | wc -l | tr -d ' ')" -eq 2 ] || fail 'Неверное количество исходных резервных копий'
for backup in "$case_home"/.bashrc.bak.*; do
    cmp -s -- "$backup" "$case_home/original-bashrc" || fail 'Резервная копия .bashrc отличается от оригинала'
done
for backup in "$case_home"/.bash_profile.bak.*; do
    cmp -s -- "$backup" "$case_home/original-profile" || fail 'Резервная копия профиля отличается от оригинала'
done

cp -- "$case_home/.bashrc" "$case_home/installed-bashrc"
cp -- "$case_home/.bash_profile" "$case_home/installed-profile"
run_installer
cmp -s -- "$case_home/.bashrc" "$case_home/installed-bashrc" || fail 'Повторная установка изменила .bashrc'
cmp -s -- "$case_home/.bash_profile" "$case_home/installed-profile" || fail 'Повторная установка изменила профиль'
[ "$(find "$case_home" -name '*.bak.*' -type f | wc -l | tr -d ' ')" -eq 2 ] || fail 'Повторная установка создала лишние копии'
[ "$(grep -c '^# >>> terminal-config bashrc >>>$' "$case_home/.bashrc")" -eq 1 ] || fail 'Повторная установка создала дубли'
check_login
[ ! -e "$case_home/omb-was-sourced" ] || fail 'Был запущен oh-my-bash'

# После переноса проекта уже установленная конфигурация остаётся самостоятельной.
moved_project="$test_directory/moved project"
case "$fixture_project:$moved_project" in
    "$test_directory"/*:"$test_directory"/*) mv -- "$fixture_project" "$moved_project" ;;
    *) fail 'Небезопасный путь переноса фикстуры' ;;
esac
fixture_project=$moved_project
check_login
run_installer
cmp -s -- "$case_home/.bashrc" "$case_home/installed-bashrc" || fail 'Перенос проекта изменил source-блок'

# Новый .bash_profile продолжает загружать прежний .profile.
case_home="$test_directory/posix profile home"
case_configuration="$case_home/.config"
mkdir -p -- "$case_home"
printf 'export TERMINAL_TEST_PROFILE=preserved\n' > "$case_home/.profile"
cp -- "$case_home/.profile" "$case_home/original-posix-profile"
run_installer
cmp -s -- "$case_home/.profile" "$case_home/original-posix-profile" || fail 'Изменён .profile'
check_login
[ "$(find "$case_home" -name '*.bak.*' -type f | wc -l | tr -d ' ')" -eq 0 ] || fail 'Созданы копии для новых файлов'

# .bash_login сохраняет исходный приоритет перед .profile.
case_home="$test_directory/bash login home"
case_configuration="$case_home/.config"
mkdir -p -- "$case_home"
printf 'export TERMINAL_TEST_PROFILE=preserved\n' > "$case_home/.bash_login"
printf 'export TERMINAL_TEST_PROFILE=wrong\n' > "$case_home/.profile"
cp -- "$case_home/.bash_login" "$case_home/original-bash-login"
cp -- "$case_home/.profile" "$case_home/original-posix-profile"
run_installer
cmp -s -- "$case_home/.bash_login" "$case_home/original-bash-login" || fail 'Изменён .bash_login'
cmp -s -- "$case_home/.profile" "$case_home/original-posix-profile" || fail 'Изменён .profile рядом с .bash_login'
check_login

# Сложные source-строки отклоняются до изменения любого startup-файла.
for complex_file in .bashrc .bash_profile; do
    case_home="$test_directory/complex $complex_file home"
    case_configuration="$case_home/.config"
    mkdir -p -- "$case_home"
    printf 'export TERMINAL_TEST_USER_LINE=preserved\n' > "$case_home/.bashrc"
    printf 'export TERMINAL_TEST_PROFILE=preserved\n' > "$case_home/.bash_profile"
    printf 'source "$HOME/oh-my-bash.sh"; export KEEP_SUFFIX=preserved\n' >> "$case_home/$complex_file"
    cp -- "$case_home/.bashrc" "$case_home/original-bashrc"
    cp -- "$case_home/.bash_profile" "$case_home/original-profile"
    if run_installer 2> "$case_home/install-error.txt"; then
        fail 'Сложная source-строка была изменена'
    fi
    grep -q 'сложную строку' "$case_home/install-error.txt" || fail 'Нет объяснения для сложной source-строки'
    cmp -s -- "$case_home/.bashrc" "$case_home/original-bashrc" || fail 'Ошибка изменила .bashrc'
    cmp -s -- "$case_home/.bash_profile" "$case_home/original-profile" || fail 'Ошибка изменила .bash_profile'
    [ "$(find "$case_home" -name '*.bak.*' -type f | wc -l | tr -d ' ')" -eq 0 ] || fail 'Отказ создал лишнюю резервную копию'
done

# Ошибка синтаксиса в любом подготовленном профиле сохраняет оба исходника.
for invalid_file in .bashrc .bash_profile; do
    case_home="$test_directory/invalid $invalid_file home"
    case_configuration="$case_home/.config"
    mkdir -p -- "$case_home"
    printf 'export TERMINAL_TEST_USER_LINE=preserved\n' > "$case_home/.bashrc"
    printf 'export TERMINAL_TEST_PROFILE=preserved\n' > "$case_home/.bash_profile"
    printf 'if true; then\n' >> "$case_home/$invalid_file"
    cp -- "$case_home/.bashrc" "$case_home/original-bashrc"
    cp -- "$case_home/.bash_profile" "$case_home/original-profile"
    if run_installer 2> "$case_home/install-error.txt"; then
        fail 'Некорректный startup-файл был применён'
    fi
    grep -q 'Ошибка синтаксиса' "$case_home/install-error.txt" || fail 'Нет объяснения для ошибки синтаксиса'
    cmp -s -- "$case_home/.bashrc" "$case_home/original-bashrc" || fail 'Ошибка синтаксиса изменила .bashrc'
    cmp -s -- "$case_home/.bash_profile" "$case_home/original-profile" || fail 'Ошибка синтаксиса изменила .bash_profile'
    [ "$(find "$case_home" -name '*.bak.*' -type f | wc -l | tr -d ' ')" -eq 0 ] || fail 'Ошибка синтаксиса создала резервную копию'
done

HOME="$case_home" bash "$fixture_project/install.sh" --help > /dev/null
if HOME="$case_home" bash "$fixture_project/install.sh" --unknown > /dev/null 2>&1; then
    fail 'Неизвестный флаг принят'
fi
printf 'PASS install.sh\n'
