#!/bin/bash

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
    echo "Environment variables loaded from .env"
else
    echo ".env file not found. Please ensure it exists."
    exit 1
fi

# Verify certificates exist
echo "Verifying certificates..."
if [ ! -f "certs/ca/ca.crt" ] || [ ! -f "certs/ca/ca.key" ] || [ ! -f "certs/instance/instance.crt" ] || [ ! -f "certs/instance/instance.key" ]; then
    echo "Warning: Some certificates are missing. Ensure all required certificates are present in certs/ca and certs/instance."
    exit 1
fi
echo "Certificates verification complete."

# Configure vm.max_map_count for Elasticsearch
echo "Setting vm.max_map_count for Elasticsearch..."
sudo sysctl -w vm.max_map_count=262144

# Start Docker containers, ensuring elasticsearch-init runs first
echo "Starting Docker containers..."
docker compose up -d elasticsearch

# Wait for Elasticsearch to fully start
echo "Waiting for Elasticsearch to start..."
timeout=120  # 2-minute timeout
start_time=$(date +%s)
while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $elapsed -gt $timeout ]; then
        echo "Timeout while waiting for Elasticsearch readiness."
        exit 1
    fi
    
    if curl --insecure -s -u elastic:${ELASTIC_PASSWORD} "https://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null; then
        echo "Elasticsearch is ready."
        break
    fi
    
    echo "Waiting for Elasticsearch readiness... ($elapsed seconds elapsed)"
    sleep 5
done

# Check if kibana_system user exists
echo "Checking for kibana_system user..."
user_check=$(docker exec elasticsearch curl --insecure -s -u elastic:${ELASTIC_PASSWORD} "https://localhost:9200/_security/user/kibana_system")

if echo "$user_check" | grep -q '"kibana_system"'; then
  echo "kibana_system user exists, resetting password..."
  
  # Reset kibana_system password with retries
  for i in {1..3}; do
    echo "Attempt $i to reset kibana_system password..."
    result=$(docker exec elasticsearch curl --insecure -s -X POST -u elastic:${ELASTIC_PASSWORD} \
        "https://localhost:9200/_security/user/kibana_system/_password" \
        -H "Content-Type: application/json" \
        -d "{\"password\": \"${KIBANA_SYSTEM_PASSWORD}\"}")
    
    if [[ "$result" == "{}" ]]; then
      echo "Password reset successfully."
      break
    else
      echo "Reset failed, retrying in 3 seconds..."
      echo "Response: $result"
      sleep 3
    fi
    
    if [ "$i" -eq 3 ]; then
      echo "Failed to reset password after 3 attempts."
      exit 1
    fi
  done
else
  echo "kibana_system user not found, creating user..."
  
  # Check if kibana_system role exists
  role_check=$(docker exec elasticsearch curl --insecure -s -u elastic:${ELASTIC_PASSWORD} \
      "https://localhost:9200/_security/role/kibana_system")
  
  if ! echo "$role_check" | grep -q '"kibana_system"'; then
    echo "kibana_system role not found, creating role..."
    docker exec elasticsearch curl --insecure -s -X POST -u elastic:${ELASTIC_PASSWORD} \
      "https://localhost:9200/_security/role/kibana_system" \
      -H "Content-Type: application/json" \
      -d '{
        "cluster": ["monitor", "manage_index_templates", "manage_ilm", "manage_ingest_pipelines"],
        "indices": [
          {
            "names": [ ".kibana*" ],
            "privileges": ["all"]
          }
        ]
      }'
  fi
  
  # Create kibana_system user
  echo "Creating kibana_system user..."
  create_result=$(docker exec elasticsearch curl --insecure -s -X POST -u elastic:${ELASTIC_PASSWORD} \
      "https://localhost:9200/_security/user/kibana_system" \
      -H "Content-Type: application/json" \
      -d "{\"password\": \"${KIBANA_SYSTEM_PASSWORD}\", \"roles\": [\"kibana_system\"], \"full_name\": \"Kibana System User\", \"email\": \"kibana@localhost\"}")
  
  echo "Creation result: $create_result"
  if [[ "$create_result" == "{}" ]]; then
    echo "kibana_system user created successfully."
  else
    echo "Failed to create kibana_system user."
    exit 1
  fi
fi

# Pause briefly after password operations
echo "Pausing briefly before starting remaining services..."
sleep 5

# Start other services
echo "Starting remaining services..."
docker compose up -d

echo "Services started successfully!"