#!/bin/bash

sysctl -w vm.max_map_count=262144

echo "vm.max_map_count est maintenant défini à:"
sysctl vm.max_map_count

sleep 2

echo "Initialisation d'Elasticsearch terminée avec succès!"