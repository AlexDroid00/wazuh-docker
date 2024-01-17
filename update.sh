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
# Verifico se mi trovo nella cartella di wazuh
if test -d wazuh-docker; then
    cd wazuh-docker/
fi
if ! test -d  single-node; then
    echo "This script must be run in Wazuh folder"
    exit 1
fi
# Verifico se i container sono attivi
cd single-node/
 if [[ $(docker compose ps --services --filter "status=running" | wc -l) != 3 ]]; then
    echo "Containers must be running"
    exit 1
fi


# Recupero i parametri
repository="https://github.com/wazuh/wazuh-docker.git"
read -p "Enter the new Wazuh version [4.7.2]: " wazuh_version
wazuh_version=${wazuh_version:-"4.7.2"}
read -p "Enter the heap size to use for Wazuh Indexer [4g]: " heap_size
heap_size=${heap_size:-"4g"}
read -p "Do you want to keep config files? [Y/n] " yn
case $yn in 
	[nN] ) 
        keep_config=false;;
	* )
        keep_config=true;;
esac
# Recupero le credenziali
container_id=$(docker compose ps -q wazuh.dashboard)
INDEXER_PASSWORD=$(docker exec $container_id bash -c 'echo "$INDEXER_PASSWORD"')
DASHBOARD_PASSWORD=$(docker exec $container_id bash -c 'echo "$DASHBOARD_PASSWORD"')
API_PASSWORD=$(docker exec $container_id bash -c 'echo "$API_PASSWORD"')

# Spegno i container
echo "Shutting down containers..."
docker compose down 2> /dev/null
echo "Done."

# Copio i file di configurazione
if [ keep_config = true ] ; then
    cp -r single-node/config /tmp/wazuh_cfg_backup
    cp single-node/docker-compose.yml /tmp/wazuh_cfg_backup/docker-compose.yml
fi

# Checkout sul nuovo branch
echo "Updating files..."
cd ..
git fetch
git checkout -f v$wazuh_version

# Riapplico le configurazioni
cd single-node/
echo "Updating docker-compose.yml..."
if grep -q "./config/wazuh_cluster/wazuh_manager.conf:/wazuh-config-mount/etc/ossec.conf" docker-compose.yml; then
    sed -i '/- \.\/config\/wazuh_cluster\/wazuh_manager.conf:\/wazuh-config-mount\/etc\/ossec.conf/d' docker-compose.yml # La configurazione si trova già nel volume wazuh_etc
    mv config/wazuh_cluster/wazuh_manager.conf config/wazuh_cluster/wazuh_manager.conf.new # Potrebbe servire
else
    echo "I was unable to remove mounting of the ossec.conf file. Configuration may be incorrect."
fi
sed -i "s/512m/$heap_size/g" docker-compose.yml # Heap size

if [ keep_config = true ] ; then
    mv /tmp/wazuh_cfg_backup/docker-compose.yml single-node/docker-compose.yml.old
    cp -r /tmp/wazuh_cfg_backup single-node/config
    rm -r /tmp/wazuh_cfg_backup
    # Riapplico le password
    sed -i "s/INDEXER_PASSWORD=SecretPassword/INDEXER_PASSWORD=$INDEXER_PASSWORD/" docker-compose.yml
    sed -i "s/DASHBOARD_PASSWORD=kibanaserver/DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD/" docker-compose.yml
    sed -i "s/API_PASSWORD=MyS3cr37P450r.*-/API_PASSWORD=$API_PASSWORD/" docker-compose.yml
fi

# Riavvio i container
echo "Done. Restarting..."
docker compose up -d --quiet-pull

echo "Done. Bye."