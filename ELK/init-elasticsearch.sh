#!/bin/bash

# Script d'initialisation pour Elasticsearch
# Ce script configure les paramètres système nécessaires pour Elasticsearch

# Définir vm.max_map_count
sysctl -w vm.max_map_count=262144

# Afficher la valeur actuelle pour vérification
echo "vm.max_map_count est maintenant défini à:"
sysctl vm.max_map_count

# Attendre que la configuration soit prise en compte
sleep 2

echo "Initialisation d'Elasticsearch terminée avec succès!"