#!/bin/bash
# install.sh: installs the NVRM from tools/nvrm/build.sh (or, with restore, nullmoth's original kept in
# ~/NVRM.kext.original) and rebuilds the auxiliary kext collection, through tools/accel/install.sh.
#   sudo bash tools/nvrm/install.sh            sudo bash tools/nvrm/install.sh restore
KX=NVRM exec bash "$(dirname "$0")/../accel/install.sh" "$@"
