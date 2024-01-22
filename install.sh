#!/bin/bash

# Verifico se lo script è stato eseguito come root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi
# Verifico se unzip è installato
if ! command -v unzip &> /dev/null; then
    echo "unzip is not installed"
    exit 1
fi
# Verifico se docker è installato
if ! command -v docker &> /dev/null; then
    echo "docker is not installed"
    exit 1
fi
# Verifico se docker compose è installato
if ! command -v docker compose &> /dev/null; then
    echo "docker compose is not installed"
    exit 1
fi

# Parametri
repository="https://github.com/wazuh/wazuh-docker.git"
custom_config_url="https://github.com/AlexDroid00/wazuh-docker/raw/main/custom_config.zip"
read -p "Enter the Wazuh version [4.7.2]: " wazuh_version
wazuh_version=${wazuh_version:-"4.7.2"}
read -p "Enter the heap size to use for Wazuh Indexer [4g]: " heap_size
heap_size=${heap_size:-"4g"}


# Configuro il memory mapping
sysctl -w vm.max_map_count=262144
sed -i '/vm.max_map_count/d' /etc/sysctl.conf
echo "vm.max_map_count=262144" | tee -a /etc/sysctl.conf

# Clono il repository Wazuh
git clone $repository -b v$wazuh_version

# Scarico la configurazione personalizzata e lo installo
cd wazuh-docker/single-node/
wget $custom_config_url -nv
mkdir custom_config
unzip custom_config.zip -d custom_config
if grep -q "./config/wazuh_cluster/wazuh_manager.conf:/wazuh-config-mount/etc/ossec.conf" docker-compose.yml; then
    sed -i '/- \.\/config\/wazuh_cluster\/wazuh_manager.conf:\/wazuh-config-mount\/etc\/ossec.conf/d' docker-compose.yml # La configurazione rimarrà nel volume wazuh_etc
    rm config/wazuh_cluster/wazuh_manager.conf # Non è più necessario
else
    echo "I was unable to remove mounting of the ossec.conf file in docker-compose.yml. Configuration may be incorrect."
fi
sed -i "s/512m/$heap_size/g" docker-compose.yml # Heap size

# Genero i certificati (se necessario) e avvio
if [[ "$@" =~ "--no-certs" ]]; then
  echo "Skipping certificate generation..."
else
  echo "Generating certs..."
  sudo docker compose -f generate-indexer-certs.yml run --rm generator
fi
sudo docker compose up -d

# Recupero l'id del container con wazuh-manager
container_id=$(docker compose ps -q wazuh.manager)

# Copio i file di configurazione
docker cp custom_config/local_rules.xml "$container_id":/var/ossec/etc/rules/local_rules.xml
docker cp custom_config/groups/. "$container_id":/var/ossec/etc/shared/.
docker cp custom_config/ossec.conf "$container_id":/var/ossec/etc/ossec.conf
docker cp custom_config/custom-ip-check.py "$container_id":/var/ossec/integrations/custom-ip-check.py
docker exec "$container_id" sh -c "echo SecurePassword > /var/ossec/etc/authd.pass"
cp custom_config/internal_users.yml config/wazuh_indexer/internal_users.yml 
docker exec "$container_id" sed -i '/archives:/{n;s/false/true/;}' /etc/filebeat/filebeat.yml # Abilito l'inoltro dei log archives

# Imposto i permessi sui file
docker exec "$container_id" chmod 660 /var/ossec/etc/ossec.conf
docker exec "$container_id" chown root:wazuh /var/ossec/etc/ossec.conf
docker exec "$container_id" chmod 750 /var/ossec/integrations/custom-ip-check.py
docker exec "$container_id" chown root:wazuh /var/ossec/integrations/custom-ip-check.py
docker exec "$container_id" chmod 640 /var/ossec/etc/authd.pass
docker exec "$container_id" chown root:wazuh /var/ossec/etc/authd.pass
docker exec "$container_id" chmod 770 /var/ossec/etc/shared/apache /var/ossec/etc/shared/nginx /var/ossec/etc/shared/iis
docker exec "$container_id" chown wazuh:wazuh -R /var/ossec/etc/shared/apache/ /var/ossec/etc/shared/nginx/ /var/ossec/etc/shared/iis/
docker exec "$container_id" chmod 640 /var/ossec/etc/shared/apache/agent.conf /var/ossec/etc/shared/nginx/agent.conf /var/ossec/etc/shared/iis/agent.conf
# Riavvio solo il server o fermo compose se non sono stati ancora generati i certificati
if [[ "$@" =~ "--no-certs" ]]; then
  docker compose down
else
  docker restart "$container_id"
fi

# Pulizia
rm -R custom_config/ custom_config.zip