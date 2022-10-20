#!/bin/bash

# Fail on error
set -euxo pipefail

UNAME_R=$(uname -r)

TARGET_VERSION='4.18.0-305.10.2.el8_4.x86_64'

if [[ "${UNAME_R}" == "${TARGET_VERSION}" ]]; then
  echo "target kernel version [${TARGET_VERSION}] is installed"
  exit 0
fi

function get_metadata_attribute() {
  local -r attribute_name=$1
  local -r default_value=$2
  /usr/share/google/get_metadata_value "attributes/${attribute_name}" || echo -n "${default_value}"
}

OS_NAME=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
DRIVER_VERSION=$(get_metadata_attribute 'gpu-driver-version' "460.32.03")
CUDA_VERSION=$(get_metadata_attribute 'cuda-version' '11.2')

# Only run this script for rock8 when targetting NVidia kernel driver 455 or earlier
if [[ ${OS_NAME} != rocky ]]; then exit 0; fi
if [[ ${DRIVER_VERSION%%.*} > "455" ]] && [[ ${CUDA_VERSION} > "11.1" ]]; then exit 0; fi

cd /tmp

function execute_with_retries() {
  local -r cmd=$1
  for ((i = 0; i < 10; i++)); do
    if eval "$cmd"; then
      return 0
    fi
    sleep 5
  done
  return 1
}

URL_PFX="http://mirror.centos.org/centos/8-stream/BaseOS/x86_64/os/Packages"
PKGS="kernel kernel-core kernel-modules kernel-headers kernel-tools kernel-tools-libs kernel-devel"

for pkg in ${PKGS}
do
  wget -q ${URL_PFX}/${pkg}-${TARGET_VERSION}.rpm
done

execute_with_retries "dnf -y -q update"
execute_with_retries "dnf install -y kernel-*${TARGET_VERSION}.rpm"

# pin the kernel packages
dnf install -y 'dnf-command(versionlock)'
for pkg in ${PKGS}
do
  dnf versionlock ${pkg}-${TARGET_VERSION}
done

# Keep the startup script from re-running
DP_ROOT=/usr/local/share/google/dataproc
STARTUP_SCRIPT="${DP_ROOT}/startup-script.sh"
sed -i -e 's:/usr/bin/env bash:/usr/bin/env bash\nexit 0:' $STARTUP_SCRIPT

systemctl reboot
