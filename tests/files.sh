#!/usr/bin/env bash
set -euo pipefail
test_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
source "$test_script_dir/../shell/files.sh"
test_base=$(cd "${TMPDIR:-/tmp}" && pwd -P)
test_root=$(mktemp -d "$test_base/terminal-files.XXXXXX")
cleanup() {
  case "$test_root" in
    "$test_base"/terminal-files.??????) rm -rf -- "$test_root" ;;
    *) printf 'Refusing unexpected cleanup path %s\n' "$test_root" >&2 ;;
  esac
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

fixture="$test_root/fixture"
mkdir "$fixture" "$fixture/adir" "$fixture/adir/level-two" "$fixture/zdir" "$fixture/.hidden-dir"
printf 'deep\n' > "$fixture/adir/level-two/deep.md"
printf 'regular\n' > "$fixture/00 file.txt"
printf 'hidden\n' > "$fixture/.secret"
printf 'literal\n' > "$fixture/"'literal $(false) [x].txt'

listing=$(terminal_ls --color=never "$fixture")
[[ $listing == *'adir/'* && $listing != *'level-two'* ]] || fail 'Default ls depth'
after_adir=${listing#*adir/}
after_zdir=${after_adir#*zdir/}
[[ $after_adir == *'zdir/'* && $after_zdir == *'00 file.txt'* ]] || fail 'Directories first'
[[ $listing != *'.secret'* && $listing != *'.hidden-dir'* ]] || fail 'Hidden entries leaked'
[[ $listing == *'literal $(false) [x].txt'* ]] || fail 'Literal filename changed'
[[ $listing != *$'\033['* ]] || fail 'Never color emitted escapes'

sort_fixture="$test_root/sorted"
mkdir "$sort_fixture" "$sort_fixture/z-dir" "$sort_fixture/a-dir"
for name in zeta alpha .bashrc .env.local b.md a.MD z.JSON a.json z.PY a.py z.TXT a.txt; do
  printf 'sort fixture\n' > "$sort_fixture/$name"
done
listing=$(LC_ALL=C terminal_ls -a --color=never "$sort_fixture")
remaining=$listing
for name in a-dir/ z-dir/ .bashrc alpha zeta a.json z.JSON .env.local a.MD b.md a.py z.PY a.txt z.TXT; do
  [[ $remaining == *"$name"* ]] || fail "Extension/name order for $name"
  remaining=${remaining#*"$name"}
done

listing=$(terminal_ls --level=2 "$fixture")
[[ $listing == *'level-two/'* && $listing != *'deep.md'* ]] || fail 'Explicit depth'
listing=$(terminal_tree "$fixture")
[[ $listing == *'deep.md'* ]] || fail 'Default tree depth'
listing=$(terminal_tree --level=0 "$fixture")
[[ $listing != *'adir/'* && $listing != *'00 file.txt'* ]] || fail 'Zero depth'
for option in -a -A; do
  listing=$(terminal_ls "$option" "$fixture")
  [[ $listing == *'.secret'* && $listing == *'.hidden-dir/'* ]] || fail 'Hidden option'
  [[ $listing != *'──  ./'* && $listing != *'──  ../'* ]] || fail 'Dot entries leaked'
done

listing=$(terminal_ls --color=always "$fixture")
[[ $listing == *$'\033[38;5;81m'* && $listing == *$'\033[0m'* ]] || fail 'Always color'
listing=$(terminal_ls --color=auto "$fixture")
[[ $listing != *$'\033['* ]] || fail 'Auto color on redirected output'
listing=$(terminal_ls "$fixture/00 file.txt" "$fixture/adir")
[[ $listing == *'00 file.txt'* && $listing == *'level-two/'* ]] || fail 'Multiple roots'

# Require actual symlinks instead of accepting MSYS's copied-file fallback.
if MSYS=winsymlinks:nativestrict ln -s adir "$fixture/link-dir" 2>/dev/null &&
  [[ -L $fixture/link-dir ]]; then
  listing=$(terminal_tree --level=3 "$fixture/link-dir")
  [[ $listing == ' '* && $listing != *'level-two'* ]] || fail 'Symlink traversal'
  listing=$(terminal_ls "$fixture")
  [[ $listing == *' link-dir'* ]] || fail 'Symlink icon'
else
  printf 'SKIP: native symlink creation unavailable\n'
fi

# Windows rejects control characters in actual filenames.
control_name=$'line\nbreak\t\r\e[31m\\file'
escaped=$(_terminal_files_name "$control_name")
[[ $escaped == 'line\nbreak\t\r\e[31m\\file' ]] || {
  printf 'Actual escaped filename %q\n' "$escaped" >&2
  printf 'Original filename %q\n' "$control_name" >&2
  fail 'Control-character escaping'
}
if { printf 'newline\n' > "$fixture/"$'line\nbreak.txt'; } 2>/dev/null; then
  listing=$(terminal_ls "$fixture")
  [[ $listing == *'line\nbreak.txt'* ]] || fail 'Control filename rendering'
fi

listing=$(terminal_ls --help)
[[ $listing == *'--level=N'* && $listing == *'-la'* ]] || fail 'Help'
listing=$(terminal_ls -la "$fixture")
native_listing=$(command ls -la "$fixture")
[[ $listing == "$native_listing" ]] || fail 'System ls fallback'
(
  cd "$fixture"
  printf 'dash\n' > '-dash.txt'
  listing=$(terminal_ls -- '-dash.txt')
  [[ $listing == *'-dash.txt'* ]] || fail 'End-of-options marker'
)
if terminal_ls "$test_root/missing" > "$test_root/out" 2> "$test_root/err"; then fail 'Missing path succeeded'; fi
[[ -s $test_root/err ]] || fail 'Missing-path diagnostic'
if terminal_ls --level=wrong > /dev/null 2>&1; then fail 'Invalid level accepted'; fi
if terminal_ls --color=wrong > /dev/null 2>&1; then fail 'Invalid color accepted'; fi

# Caller glob flags and IFS must survive even empty-directory traversal.
shopt -s failglob nocaseglob
set -f
glob_before=$(shopt -p nullglob dotglob failglob nocaseglob || :)
saved_ifs=$IFS
IFS=:
terminal_ls --color=never "$fixture" > /dev/null
[[ $IFS == : && $- == *f* ]] || fail 'Caller shell state changed'
glob_after=$(shopt -p nullglob dotglob failglob nocaseglob || :)
[[ $glob_before == "$glob_after" ]] || fail 'Caller glob options changed'
IFS=$saved_ifs
printf 'PASS: file tree order, depth, hidden entries, names, colors, errors and shell state\n'
