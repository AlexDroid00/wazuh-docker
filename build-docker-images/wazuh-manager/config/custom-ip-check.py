#!/var/ossec/framework/python/bin/python3

###
# COSTANTI
###
blacklist_urls = [
    "http://iplists.firehol.org/files/firehol_level3.netset",
    "http://iplists.firehol.org/files/firehol_level2.netset",
]  # Lists will be parsed in order. Use only HTTP.

whitelist = [
    
] # You can use CIDR notation

update_interval = 60 * 60 * 12 #seconds*minutes*hours --> value must be in seconds

import sys
import json
import os
import ipaddress
import time
import urllib.request
from socket import socket, AF_UNIX, SOCK_DGRAM


def in_blacklist(srcip: str, urls: list = blacklist_urls) -> bool:
    """
    Controlla se l'indirizzo IP si trova tra le subnet indicate nei file
    di blacklist. Ritorna True se lo trova, False altrimenti
    """
    check_and_download_blacklists()
    ip = ipaddress.ip_address(srcip)
    for i in range(len(urls)):
        file_path = f"tmp/{i}.list"
        with open(file_path, "r") as f:
            subnet_list = [line.strip() for line in f if not line.startswith("#")]
            for subnet in subnet_list:
                if ip in ipaddress.ip_network(subnet):
                    return True
    return False

def in_whitelist(srcip: str, whitelist: list = whitelist) -> bool:
    """
    Controlla se l'indirizzo IP si trova all'interno delle subnet definite
    in whitelist. Ritorna True se lo trova, False altrimenti
    """
    ip = ipaddress.ip_address(srcip)
    for subnet in whitelist:
        if ip in ipaddress.ip_network(subnet):
            return True
    return False


def check_and_download_blacklists(urls: list = blacklist_urls) -> None:
    """
    Controllo se le blacklist non esistono o se sono più vecchie di 12h.
    In caso positivo, scarico la nuova versione.
    In caso negativo, non faccio nulla.
    Si presuppone che i nomi dei file siano formattati come {0..n}.list
    """
    for i in range(len(urls)):
        file_path = f"tmp/{i}.list"
        if os.path.exists(file_path):
            last_file_mod_time = os.path.getmtime(file_path)
            current_time = time.time()
            if current_time - last_file_mod_time < update_interval:
                pass
        # File download
        req = urllib.request.Request(urls[i], headers={"User-Agent": "Mozilla/5.0"})
        response = urllib.request.urlopen(req)
        data = response.read()
        with open(file_path, "wb") as f:
            f.write(data)


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
# Read alert file name from sys args
alert_file = open(sys.argv[1])

# Read the alert file
alert = json.loads(alert_file.read())
alert_file.close()

# Extract srcip field
if "data" not in alert or "srcip" not in alert["data"]:
    sys.exit(0)
srcip = alert["data"]["srcip"]

# Checking if IP is in the blacklist
if not in_whitelist(srcip) and in_blacklist(srcip):
    # Ip found. Creating alert
    alert_output = {}
    alert_output["ip-check"] = {"found": 1}
    alert_output["integration"] = "custom-ip-check"
    alert_output["srcip"] = srcip
    alert_output["source"] = {}
    alert_output["source"]["alert_id"] = alert["id"]
    alert_output["source"]["rule"] = alert["rule"]
    alert_output["source"]["description"] = alert["rule"]["description"]
    alert_output["source"]["full_log"] = alert["full_log"]
    send_event(alert_output, alert["agent"])

sys.exit(0)