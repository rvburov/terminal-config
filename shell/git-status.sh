# Bash 3.2+. Source this file before calling terminal_git_status.
# Counts represent changed paths. Unmerged paths count only as conflicts.

terminal_git_status() {
  TERMINAL_GIT_BRANCH=''
  TERMINAL_GIT_STAGED=0
  TERMINAL_GIT_UNSTAGED=0
  TERMINAL_GIT_UNTRACKED=0
  TERMINAL_GIT_CONFLICTS=0
  TERMINAL_GIT_AHEAD=0
  TERMINAL_GIT_BEHIND=0

  local record rename_source branch_oid='' branch_head=''
  local staged=0 unstaged=0 untracked=0 conflicts=0 ahead=0 behind=0
  local git_exit_code=1 branch_divergence index_status worktree_status

  while IFS= read -r -d '' record; do
    case "$record" in
      '# branch.oid '*)
        branch_oid=${record#'# branch.oid '}
        ;;
      '# branch.head '*)
        branch_head=${record#'# branch.head '}
        ;;
      '# branch.ab '*)
        branch_divergence=${record#'# branch.ab '}
        ahead=${branch_divergence%% *}
        ahead=${ahead#+}
        behind=${branch_divergence#* }
        behind=${behind#-}
        ;;
      '1 '*|'2 '*)
        index_status=${record:2:1}
        worktree_status=${record:3:1}
        if [[ $index_status != '.' ]]; then
          staged=$((staged + 1))
        fi
        if [[ $worktree_status != '.' ]]; then
          unstaged=$((unstaged + 1))
        fi

        # A rename/copy record has a second NUL-delimited original pathname.
        # Consume it without interpreting any of its characters as status data.
        if [[ $record == '2 '* ]]; then
          if ! IFS= read -r -d '' rename_source; then
            break
          fi
        fi
        ;;
      '? '*)
        untracked=$((untracked + 1))
        ;;
      'u '*)
        conflicts=$((conflicts + 1))
        ;;
      '# terminal.exit '*)
        git_exit_code=${record#'# terminal.exit '}
        ;;
    esac
  done < <(
    # The trailing record carries the exit status out of process substitution.
    # Keeping Git in an if condition also handles callers using errexit.
    if command git --no-optional-locks status --porcelain=v2 -z \
      --branch --ahead-behind --untracked-files=normal 2>/dev/null; then
      printf '# terminal.exit 0\0'
    else
      printf '# terminal.exit %s\0' "$?"
    fi
  )

  if [[ $git_exit_code != 0 || -z $branch_head || -z $branch_oid ]]; then
    return 1
  fi

  if [[ $branch_head == '(detached)' ]]; then
    branch_head=${branch_oid:0:7}
  fi

  TERMINAL_GIT_BRANCH=$branch_head
  TERMINAL_GIT_STAGED=$staged
  TERMINAL_GIT_UNSTAGED=$unstaged
  TERMINAL_GIT_UNTRACKED=$untracked
  TERMINAL_GIT_CONFLICTS=$conflicts
  TERMINAL_GIT_AHEAD=$ahead
  TERMINAL_GIT_BEHIND=$behind
  return 0
}
