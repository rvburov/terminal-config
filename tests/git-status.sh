#!/usr/bin/env bash
set -euo pipefail

test_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
source "$test_script_dir/../shell/git-status.sh"

# Keep the fixtures independent of a caller's repository and Git preferences.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_COUNT
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

test_base=$(cd "${TMPDIR:-/tmp}" && pwd -P)
test_root=$(mktemp -d "$test_base/terminal-git-status.XXXXXX")
cleanup() {
  # Delete only the absolute, freshly allocated fixture directory.
  case "$test_root" in
    "$test_base"/terminal-git-status.??????) rm -rf -- "$test_root" ;;
    *) printf 'Refusing to remove unexpected test path: %s\n' "$test_root" >&2 ;;
  esac
}
trap cleanup EXIT
mkdir "$test_root/empty" "$test_root/nonrepo"
stdout_file="$test_root/stdout"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_git() {
  command git -c user.name='Terminal Config Test' \
    -c user.email='terminal-config-test@example.invalid' \
    -c commit.gpgsign=false -c core.hooksPath="$test_root/empty" "$@"
}

expect_status() {
  local expected_branch=$1
  shift
  terminal_git_status > "$stdout_file" || fail 'Repository status failed'
  [[ ! -s $stdout_file ]] || fail 'API wrote to stdout'
  [[ $TERMINAL_GIT_BRANCH == "$expected_branch" ]] || fail "Unexpected branch: $TERMINAL_GIT_BRANCH"
  local counts="$TERMINAL_GIT_STAGED $TERMINAL_GIT_UNSTAGED $TERMINAL_GIT_UNTRACKED $TERMINAL_GIT_CONFLICTS $TERMINAL_GIT_AHEAD $TERMINAL_GIT_BEHIND"
  [[ $counts == "$*" ]] || fail "Unexpected counts: $counts (expected $*)"
}

expect_empty_status() {
  if terminal_git_status > "$stdout_file"; then
    fail 'Status unexpectedly succeeded'
  fi
  [[ ! -s $stdout_file && -z $TERMINAL_GIT_BRANCH ]] || fail 'Failed status kept output or a branch'
  [[ "$TERMINAL_GIT_STAGED $TERMINAL_GIT_UNSTAGED $TERMINAL_GIT_UNTRACKED $TERMINAL_GIT_CONFLICTS $TERMINAL_GIT_AHEAD $TERMINAL_GIT_BEHIND" == '0 0 0 0 0 0' ]] || fail 'Failed status kept counters'
}

test_git init -q --template="$test_root/empty" "$test_root/repo"
cd "$test_root/repo"
branch=$(test_git symbolic-ref --short HEAD)
expect_status "$branch" 0 0 0 0 0 0

# This legal Windows filename looks like a porcelain record when not skipped.
tracked_file='1 M. looks like status.txt'
printf 'original\n' > "$tracked_file"
test_git add -- "$tracked_file"
test_git commit -qm 'Initial fixture'
expect_status "$branch" 0 0 0 0 0 0

printf 'changed\n' >> "$tracked_file"
printf 'staged\n' > 'staged file.txt'
printf 'untracked\n' > 'untracked file.txt'
test_git add -- 'staged file.txt'
expect_status "$branch" 1 1 1 0 0 0
test_git add -- "$tracked_file"
test_git commit -qm 'Changed fixture'
rm -- 'untracked file.txt'
test_git mv -- "$tracked_file" 'renamed file.txt'
expect_status "$branch" 1 0 0 0 0 0
test_git commit -qm 'Renamed fixture'

test_git checkout -qb conflict-side
printf 'side\n' > 'renamed file.txt'
test_git add -- 'renamed file.txt'
test_git commit -qm 'Side fixture'
test_git checkout -q "$branch"
printf 'main\n' > 'renamed file.txt'
test_git add -- 'renamed file.txt'
test_git commit -qm 'Main fixture'
if test_git merge --no-ff --no-edit conflict-side > "$test_root/merge-output" 2>&1; then
  fail 'Conflict fixture unexpectedly merged'
fi
expect_status "$branch" 0 0 0 1 0 0
test_git merge --abort

# A local bare origin tests divergence without contacting a network service.
test_git init --bare -q --template="$test_root/empty" "$test_root/origin.git"
test_git remote add origin "$test_root/origin.git"
test_git push -qu origin "$branch"
test_git commit --allow-empty -qm 'Local ahead'
expect_status "$branch" 0 0 0 0 1 0
test_git clone -q --branch "$branch" "$test_root/origin.git" "$test_root/other"
test_git -C "$test_root/other" commit --allow-empty -qm 'Remote ahead'
test_git -C "$test_root/other" push -q origin "$branch"
test_git fetch -q origin
expect_status "$branch" 0 0 0 0 1 1

test_git checkout -q --detach
head_oid=$(test_git rev-parse HEAD)
expect_status "${head_oid:0:7}" 0 0 0 0 0 0
test_git worktree add -q --detach "$test_root/worktree"
cd "$test_root/worktree"
printf 'worktree\n' > 'worktree file.txt'
expect_status "${head_oid:0:7}" 0 0 1 0 0 0
cd "$test_root/nonrepo"
expect_empty_status

# Windows cannot create LF-containing filenames. Feed valid NUL records through
# a temporary Git executable to exercise those paths and partial-command failure.
mkdir "$test_root/fake-bin"
cat > "$test_root/fake-bin/git" <<'FAKE_GIT'
#!/usr/bin/env bash
cat "$TERMINAL_GIT_TEST_FIXTURE"
exit "${TERMINAL_GIT_TEST_EXIT:-0}"
FAKE_GIT
chmod +x "$test_root/fake-bin/git"
fixture="$test_root/porcelain"
{
  printf '# branch.oid %s\0' "$head_oid"
  printf '# branch.head %s\0' 'feature/$(false)'
  printf '# branch.ab +12 -34\0'
  printf '2 R. N... 100644 100644 100644 %s %s R100 renamed\nfile\0' "$head_oid" "$head_oid"
  printf '1 M. original\nfile\0'
  printf '1 .M N... 100644 100644 100644 %s %s modified\nfile\0' "$head_oid" "$head_oid"
  printf '? untracked\nfile\0'
  printf 'u UU N... 100644 100644 100644 100644 %s %s %s conflict\nfile\0' "$head_oid" "$head_oid" "$head_oid"
} > "$fixture"
PATH="$test_root/fake-bin:$PATH" TERMINAL_GIT_TEST_FIXTURE="$fixture" \
  expect_status 'feature/$(false)' 1 1 1 1 12 34
PATH="$test_root/fake-bin:$PATH" TERMINAL_GIT_TEST_FIXTURE="$fixture" \
  TERMINAL_GIT_TEST_EXIT=2 expect_empty_status

printf 'PASS: git status API, real repositories, rename records, newline paths and failures\n'
