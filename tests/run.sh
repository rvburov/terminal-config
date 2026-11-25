#!/usr/bin/env bash
set -euo pipefail
test_directory=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
bash "$test_directory/git-status.sh"
bash "$test_directory/install.sh"
bash "$test_directory/prompt.sh"
bash "$test_directory/files.sh"
