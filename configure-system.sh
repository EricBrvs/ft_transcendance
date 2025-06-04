#!/bin/bash
sudo sysctl -w vm.max_map_count=262144

echo "Configuring vm.max_map_count permanently..."
if [ ! -f ./ELK/elasticsearch-sysctl.conf ]; then
    mkdir -p ./ELK
    echo "vm.max_map_count=262144" > ./ELK/elasticsearch-sysctl.conf    fi

    sudo cp ./ELK/elasticsearch-sysctl.conf /etc/sysctl.d/60-elasticsearch.conf
    sudo sysctl --system

echo "Permanent configuration complete."
echo "System is now configured for Elasticsearch."
