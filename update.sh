#!/bin/bash

# Parametri
wazuh_version="4.7.1"
repository="https://github.com/wazuh/wazuh-docker.git"
custom_config_url="https://github.com/AlexDroid00/wazuh-docker/raw/main/custom_config.zip"

# Verifico se lo script è stato eseguito come root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi
# Verifica se unzip è installato
if ! command -v unzip &> /dev/null; then
    echo "unzip is not installed"
    exit 1
fi
# Verifica se docker è installato
if ! command -v docker &> /dev/null; then
    echo "docker is not installed"
    exit 1
fi
# Verifica se docker-compose è installato
if ! command -v docker compose &> /dev/null; then
    echo "docker compose is not installed"
    exit 1
fi

# Spegno i container
cd wazuh-docker/single-node/
echo "Shutting down containers..."
docker compose down 2> /dev/null
echo "Done."

# Checkout sul nuovo branch
echo "Updating files..."
cd ..
git fetch
git checkout -f v$wazuh_version

# Riapplico il file di configurazione ossec.conf
cd single-node/
wget $custom_config_url -nv
mkdir custom_config
unzip custom_config.zip -d custom_config
if grep -q "./config/wazuh_cluster/wazuh_manager.conf:/wazuh-config-mount/etc/ossec.conf" docker-compose.yml; then
    sed -i '/- \.\/config\/wazuh_cluster\/wazuh_manager.conf:\/wazuh-config-mount\/etc\/ossec.conf/d' docker-compose.yml # La configurazione si trova già nel volume wazuh_etc
    mv config/wazuh_cluster/wazuh_manager.conf config/wazuh_cluster/wazuh_manager.conf.new # Per riferimenti futuri
else
    echo "I was unable to remove mounting of the ossec.conf file. Configuration may be incorrect."
fi

# Riavvio i container
echo "Done. Restarting..."
docker compose up -d --quiet-pull

# Pulizia
echo "Done. Cleaning..."
rm -R custom_config/ custom_config.zip

echo "Done. Bye."