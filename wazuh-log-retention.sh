#!/bin/bash

retention_days=120
manager_container_name="single-node-wazuh.manager-1"
indexer_container_name="single-node-wazuh.indexer-1"

# Wazuh-Manager alerts and archives logs
docker exec "$manager_container_name" find /var/ossec/logs/alerts/ /var/ossec/logs/archives/ -type f -mtime +$retention_days -delete
docker exec "$manager_container_name" find /var/ossec/logs/alerts/ /var/ossec/logs/archives/ -empty -type d -delete

# Wazuh-Indexer logs
docker exec "$indexer_container_name" find /var/log/wazuh-indexer/ -type f -mtime +$retention_days -delete
