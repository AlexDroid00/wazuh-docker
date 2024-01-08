#!/var/ossec/framework/python/bin/python3

"""
Script di integrazione Wazuh per il controllo IP con blacklists

Autore: Alessandro Schivano
"""

BLACKLIST_URLS = [
    "http://iplists.firehol.org/files/firehol_level3.netset",
    "http://iplists.firehol.org/files/firehol_level2.netset",
]  # Lists will be parsed in order. Use only HTTP.

WHITELIST = [
    
] # You can use CIDR notation

BLACKLIST_DIR = 'tmp'
UPDATE_INTERVAL = 60 * 60 * 12 # seconds*minutes*hours --> value must be in seconds
LOG_FILE_PATH = 'logs/integrations.log'


import sys
import json
import os
import ipaddress
import time
import urllib.request
import logging
from socket import socket, AF_UNIX, SOCK_DGRAM

logging.basicConfig(filename=LOG_FILE_PATH, encoding='utf-8', level=logging.INFO, format='%(asctime)s ip-check[%(process)d]: %(levelname)s: %(message)s')


def in_blacklist(srcip: str, urls: list = BLACKLIST_URLS) -> bool:
    """
    Controlla se l'indirizzo IP si trova in una delle subnet indicate nei file di blacklist. 
    Ritorna True se lo trova, False altrimenti.
    """
    check_and_download_blacklists()
    ip = ipaddress.ip_address(srcip)
    for i, url in enumerate(urls):
        file_path = file_path = os.path.join(BLACKLIST_DIR, f"{i}.list")
        with open(file_path, "r") as f:
            subnet_list = [line.strip() for line in f if not line.startswith("#")]
            for subnet in subnet_list:
                if ip in ipaddress.ip_network(subnet):
                    return True
    return False

def in_whitelist(srcip: str, whitelist: list = WHITELIST) -> bool:
    """
    Controlla se l'indirizzo IP si trova all'interno di una delle subnet definite nella whitelist.
    Ritorna True se lo trova, False altrimenti.
    """
    ip = ipaddress.ip_address(srcip)
    for subnet in whitelist:
        if ip in ipaddress.ip_network(subnet):
            return True
    return False


def check_and_download_blacklists(urls: list = BLACKLIST_URLS) -> None:
    """
    Controllo se le blacklist non esistono o se sono più vecchie di 12h (o UPDATE_INTERVAL).
    In caso positivo, scarico la nuova versione.
    In caso negativo, non faccio nulla.
    Si presuppone che i nomi dei file siano formattati come {0..n}.list
    """
    for i, url in enumerate(urls):
        file_path = os.path.join(BLACKLIST_DIR, f"{i}.list")
        if os.path.exists(file_path):
            last_file_mod_time = os.path.getmtime(file_path)
            current_time = time.time()
            if current_time - last_file_mod_time < UPDATE_INTERVAL:
                pass
        try:
            # File download
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            response = urllib.request.urlopen(req)
            data = response.read()
            with open(file_path, "wb") as f:
                f.write(data)
            logging.info(f"Successfully downloaded list {i}")
        except Exception as e:
            logging.error(f"Error downloading blacklist from {url}: {e}")


def send_event(msg, agent=None):
    """
    Invia l'alert a Wazuh Manager utilizzando il socket.

    Copyright (C) 2015-2022, Wazuh Inc.
    """
    if not agent or agent["id"] == "000":
        string = "1:ip-check:{0}".format(json.dumps(msg))
    else:
        string = "1:[{0}] ({1}) {2}->ip-check:{3}".format(
            agent["id"],
            agent["name"],
            agent["ip"] if "ip" in agent else "any",
            json.dumps(msg),
        )
    pwd = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    socket_addr = "{0}/queue/sockets/queue".format(pwd)
    sock = socket(AF_UNIX, SOCK_DGRAM)
    sock.connect(socket_addr)
    sock.send(string.encode())
    sock.close()


"""
MAIN
"""
try:
    # Read alert file name from sys args
    alert_file = open(sys.argv[1])
    # Read the alert file
    alert = json.loads(alert_file.read())
    alert_file.close()
except Exception as e:
    logging.error(f"Error reading alert: {e}")
    sys.exit(1)

# Extract ip field
srcip = None
if "data" in alert:
    # Linux srcip
    if "srcip" in alert["data"]:
        srcip = alert["data"]["srcip"] # Found data.srcip
    # Windows srcip
    elif "win" in alert["data"] and "eventdata" in alert["data"]["win"]:
        if "remoteAddress" in alert["data"]["win"]["eventdata"]:
            logging.debug("Found Windows Event with srcip.")
            srcip = alert["data"]["win"]["eventdata"]["remoteAddress"] # Found data.win.eventdata.remoteAddress
        elif "ipAddress" in alert["data"]["win"]["eventdata"]:
            logging.debug("Found Windows Event with srcip.")
            srcip = alert["data"]["win"]["eventdata"]["ipAddress"] # Found data.win.eventdata.ipAddress
if not srcip:
    logging.debug("No srcip. Exiting.")
    sys.exit(0)

# Checking if IP is in the blacklist
if not in_whitelist(srcip) and in_blacklist(srcip):
    # Ip found. Creating alert
    logging.info(f"{srcip} found in blacklist.")
    alert_output = {
        "ip-check": {"found": 1},
        "integration": "custom-ip-check",
        "srcip": srcip,
        "source": {
            "alert_id": alert["id"],
            "rule": alert["rule"],
            "description": alert["rule"]["description"],
            "full_log": alert["full_log"],
        },
    }
    send_event(alert_output, alert["agent"])
else:
    logging.info(f"{srcip} NOT found in blacklist.")

sys.exit(0)