#!/usr/bin/env bash
# Try install.sh on a fresh Linux box in Docker, then check the result with verify.sh.
#   scripts/test-linux.sh full     --full on a box with sudo and only git preinstalled
#   scripts/test-linux.sh editor   --editor --no-sudo on a box without sudo that already has the
#                                  distro's Node and Python, which must stay untouched
#   IMAGE=debian:12 scripts/test-linux.sh full   another apt-based image (default ubuntu:24.04)
# Uses this checkout as it is on disk, but the repo-clean check compares against HEAD, so commit
# first. Takes a few minutes.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-ubuntu:24.04}"
MODE="${1:-full}"

case "$MODE" in
  full)
    packages="git sudo ca-certificates"
    user_setup="echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev"
    flags="--full"
    ;;
  editor)
    packages="git curl xz-utils ca-certificates nodejs python3"
    user_setup="true"
    flags="--editor --no-sudo"
    ;;
  *) echo "usage: $0 [full | editor]"; exit 1 ;;
esac

tag="dotfiles-test:$MODE"
docker build -q -t "$tag" - >/dev/null <<EOF
FROM $IMAGE
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y $packages \
 && useradd -m -s /bin/bash dev && $user_setup
USER dev
WORKDIR /home/dev
ENV SHELL=/bin/bash
EOF

echo "testing install.sh $flags on $IMAGE ($MODE)"
docker run --rm -e GITHUB_TOKEN -v "$DOTFILES:/src:ro" "$tag" bash -c "
  set -e
  cp -r /src ~/dotfiles
  git -C ~/dotfiles config core.fileMode false
  ~/dotfiles/install.sh $flags
  echo '--- verify (new login shell)'
  bash -lic ~/dotfiles/scripts/verify.sh
  if [ $MODE = editor ]; then
    echo '--- the distro Node and Python are untouched'
    bash -lic 'test \"\$(command -v node)\" = /usr/bin/node && test \"\$(command -v python3)\" = /usr/bin/python3 && node --version && python3 --version'
    echo '  ok  node and python3 are still /usr/bin'
  fi
  echo '--- re-run changes nothing'
  out=\$(~/dotfiles/install.sh $flags 2>&1)
  if grep -E 'linked|moved|updated .* block|added' <<<\"\$out\"; then echo 'FAIL: re-run changed something'; exit 1; fi
  echo '  ok  re-run made no changes'
  echo '--- install leaves the repo untouched'
  dirty=\$(git -C ~/dotfiles status --porcelain)
  if [ -n \"\$dirty\" ]; then echo \"FAIL: repo changed:\"; echo \"\$dirty\"; git -C ~/dotfiles diff; exit 1; fi
  echo '  ok  no changes in the repo'
"
