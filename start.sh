#!/bin/bash

# Chargement des variables d'environnement
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
    echo "Variables d'environnement chargées depuis .env"
else
    echo "Fichier .env non trouvé. Assurez-vous qu'il existe."
    exit 1
fi

# Configure le paramètre vm.max_map_count pour Elasticsearch
echo "Configuration de vm.max_map_count pour Elasticsearch..."
sudo sysctl -w vm.max_map_count=262144

# Lance les conteneurs Docker en s'assurant que elasticsearch-init s'exécute en premier
echo "Démarrage des conteneurs..."
docker compose up -d elasticsearch

# Attendre que Elasticsearch démarre complètement
echo "Attente du démarrage complet d'Elasticsearch..."
timeout=120  # Timeout de 2 minutes
start_time=$(date +%s)
while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $elapsed -gt $timeout ]; then
        echo "Timeout dépassé en attendant qu'Elasticsearch soit prêt"
        exit 1
    fi
    
    if curl -s -u elastic:${ELASTIC_PASSWORD} "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null; then
        echo "Elasticsearch est prêt"
        break
    fi
    
    echo "En attente qu'Elasticsearch soit prêt... ($elapsed secondes écoulées)"
    sleep 5
done

# Vérifier si l'utilisateur kibana_system existe
echo "Vérification de l'existence de l'utilisateur kibana_system..."
user_check=$(docker exec elasticsearch curl -s -u elastic:${ELASTIC_PASSWORD} "http://localhost:9200/_security/user/kibana_system")

if echo "$user_check" | grep -q "\"kibana_system\""; then
  echo "L'utilisateur kibana_system existe, réinitialisation du mot de passe..."
  
  # Réinitialiser le mot de passe de kibana_system
  for i in {1..3}; do
    echo "Tentative $i de réinitialisation du mot de passe kibana_system..."
    result=$(docker exec elasticsearch curl -s -X POST -u elastic:${ELASTIC_PASSWORD} "http://localhost:9200/_security/user/kibana_system/_password" -H "Content-Type: application/json" -d "{\"password\": \"${KIBANA_SYSTEM_PASSWORD}\"}")
    
    if [[ "$result" == "{}" ]]; then
      echo "Mot de passe réinitialisé avec succès!"
      break
    else
      echo "Échec de la réinitialisation, nouvelle tentative dans 3 secondes..."
      echo "Réponse: $result"
      sleep 3
    fi
    
    if [ "$i" -eq 3 ]; then
      echo "Impossible de réinitialiser le mot de passe après 3 tentatives."
      exit 1
    fi
  done
else
  echo "L'utilisateur kibana_system n'existe pas, création de l'utilisateur..."
  
  # Vérifier si le rôle kibana_system existe
  role_check=$(docker exec elasticsearch curl -s -u elastic:${ELASTIC_PASSWORD} "http://localhost:9200/_security/role/kibana_system")
  
  if ! echo "$role_check" | grep -q "\"kibana_system\""; then
    echo "Le rôle kibana_system n'existe pas, création du rôle..."
    docker exec elasticsearch curl -s -X POST -u elastic:${ELASTIC_PASSWORD} "http://localhost:9200/_security/role/kibana_system" -H "Content-Type: application/json" -d '{
      "cluster": ["monitor", "manage_index_templates", "manage_ilm", "manage_ingest_pipelines"],
      "indices": [
        {
          "names": [ ".kibana*" ],
          "privileges": ["all"]
        }
      ]
    }'
  fi
  
  # Créer l'utilisateur kibana_system
  create_result=$(docker exec elasticsearch curl -s -X POST -u elastic:${ELASTIC_PASSWORD} "http://localhost:9200/_security/user/kibana_system" -H "Content-Type: application/json" -d "{
    \"password\": \"${KIBANA_SYSTEM_PASSWORD}\",
    \"roles\": [\"kibana_system\"],
    \"full_name\": \"Kibana System User\",
    \"email\": \"kibana@localhost\"
  }")
  
  echo "Résultat de la création: $create_result"
  
  if [[ "$create_result" == "{}" ]]; then
    echo "Utilisateur kibana_system créé avec succès!"
  else
    echo "Échec de la création de l'utilisateur kibana_system."
    exit 1
  fi
fi

# Attendre un peu après la réinitialisation
sleep 5

# Démarrer les autres services
echo "Démarrage des autres services..."
docker compose up -d

echo "Service démarré avec succès!"
