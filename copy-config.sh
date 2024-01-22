#!/bin/bash

custom_config_url="https://github.com/AlexDroid00/wazuh-docker/raw/main/custom_config.zip"

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

# Cambio le password
bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/wazuh-passwords-tool.sh -a -gf wazuh-passwords.txt

# Fermo i servizi
echo "Stopping services..."
service wazuh-manager stop
service wazuh-dashboard stop
service wazuh-indexer stop

# Scarico la configurazione personalizzata
echo "Downloading configs..."
wget $custom_config_url -nv
mkdir custom_config
unzip -q custom_config.zip -d custom_config

# Copio i file di configurazione
echo "Coping configs..."
cp custom_config/local_rules.xml /var/ossec/etc/rules/local_rules.xml
cp -r custom_config/groups/* /var/ossec/etc/shared/.
cp custom_config/ossec.conf /var/ossec/etc/ossec.conf
cp custom_config/custom-ip-check.py /var/ossec/integrations/custom-ip-check.py
echo SecurePassword > /var/ossec/etc/authd.pass
sed -i '/archives:/{n;s/false/true/;}' /etc/filebeat/filebeat.yml # Abilito l'inoltro dei log archives

# Imposto i permessi sui file
echo "Setting permissions..."
chmod 750 /var/ossec/integrations/custom-ip-check.py
chown root:wazuh /var/ossec/integrations/custom-ip-check.py
chmod 640 /var/ossec/etc/authd.pass
chown root:wazuh /var/ossec/etc/authd.pass
chmod 770 /var/ossec/etc/shared/apache /var/ossec/etc/shared/nginx /var/ossec/etc/shared/iis
chown wazuh:wazuh -R /var/ossec/etc/shared/apache/ /var/ossec/etc/shared/nginx/ /var/ossec/etc/shared/iis/
chmod 640 /var/ossec/etc/shared/apache/agent.conf /var/ossec/etc/shared/nginx/agent.conf /var/ossec/etc/shared/iis/agent.conf

# Riavvio i servizi
echo "Restarting services..."
service wazuh-indexer start
service wazuh-manager start
service wazuh-dashboard start

# Pulizia
echo "Done. Cleaning..."
rm -R custom_config/ custom_config.zip