#!/bin/bash
set -u

CC=$(which clang++)
if [[ ! -x "${CC}" ]]; then
  echo "ABORTING: no compiler detected"
  exit 1
fi

CompileFlags="-O3 -Ofast"
LinkFlags="-Wformat"

# alacritree-ab/round.ps1 loads sgrtest and scrolltest_ab from the repo root by
# name, so those output names are the interface and not a preference.
build() {
  local source=$1 output=$2
  echo "Building release: ./${output}"
  "${CC}" ${CompileFlags} ${LinkFlags} "instruments/${source}" -o "${output}" && strip "${output}"
}

build termbench.cpp  termbench_release_clang
build termbench.cpp  termbench_ab
build sgrtest.cpp    sgrtest
build scrolltest.cpp scrolltest_ab
