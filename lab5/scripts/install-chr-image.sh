#!/usr/bin/env bash
set -e

CHR_VERSION="7.23.8"
VRNETLAB_DIR="/tmp/vrnetlab-check"
WORK_DIR="/tmp/chr-build"

# vmdk chr
CHR_URL="https://download.mikrotik.com/routeros/${CHR_VERSION}/chr-${CHR_VERSION}.vmdk.zip"
# итоговый Docker image
IMAGE_NAME="vrnetlab/mikrotik_routeros:${CHR_VERSION}"

# зависимости
sudo apt-get update
sudo apt-get install -y git wget unzip make docker.io
sudo systemctl enable --now docker

# очистка и переход в рабочую папку
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# скачивание и распаковка образа
wget -O "chr-${CHR_VERSION}.vmdk.zip" "${CHR_URL}"
unzip -o "chr-${CHR_VERSION}.vmdk.zip"

# получение srl-labs/vrnetlab
rm -rf "${VRNETLAB_DIR}"
git clone --depth 1 https://github.com/srl-labs/vrnetlab.git "${VRNETLAB_DIR}"

# копия vmdk для создания Docker Image
cd "${VRNETLAB_DIR}/mikrotik/routeros"
cp "${WORK_DIR}/chr-${CHR_VERSION}.vmdk" "./chr-${CHR_VERSION}.vmdk"

# сборка Docker Image
make docker-image IMAGE="chr-${CHR_VERSION}.vmdk" DOCKER_BUILD_CMD='docker build --network=host'