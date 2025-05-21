#!/bin/bash

sudo sysctl -w vm.max_map_count=262144

echo "Configurant vm.max_map_count de manière permanente..."
sudo cp ./ELK/elasticsearch-sysctl.conf /etc/sysctl.d/60-elasticsearch.conf
sudo sysctl --system

echo "Configuration permanente terminée."
echo "Vous n'aurez plus besoin d'exécuter sysctl -w vm.max_map_count=262144 après un redémarrage."
