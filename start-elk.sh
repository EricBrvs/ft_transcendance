#!/bin/bash

# Script to configure and start the ELK stack directly with HTTPS

echo "Configuring and starting the ELK stack with HTTPS..."

# 1. Stop all containers
echo "Stopping containers..."
docker compose down

# 2. Configure with SSL
echo "Applying SSL configuration..."

# Update elasticsearch.yml
cat > ./ELK/elasticsearch/config/elasticsearch.yml << EOF
cluster.name: "docker-cluster"
network.host: 0.0.0.0
discovery.type: single-node
xpack.security.enabled: true
xpack.security.authc.api_key.enabled: true

# SSL/TLS Configuration
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.key: /usr/share/elasticsearch/config/certs/instance/instance.key
xpack.security.http.ssl.certificate: /usr/share/elasticsearch/config/certs/instance/instance.crt
xpack.security.http.ssl.certificate_authorities: [ "/usr/share/elasticsearch/config/certs/ca/ca.crt" ]
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.key: /usr/share/elasticsearch/config/certs/instance/instance.key
xpack.security.transport.ssl.certificate: /usr/share/elasticsearch/config/certs/instance/instance.crt
xpack.security.transport.ssl.certificate_authorities: [ "/usr/share/elasticsearch/config/certs/ca/ca.crt" ]
xpack.security.transport.ssl.verification_mode: certificate

bootstrap.memory_lock: true
xpack.ml.enabled: false
xpack.watcher.enabled: false
EOF

# Update kibana.yml
cat > ./ELK/kibana/config/kibana.yml << EOF
server.name: kibana
server.host: "0.0.0.0"

# HTTPS connection to Elasticsearch
elasticsearch.hosts: ["https://elasticsearch:9200"]
elasticsearch.ssl.verificationMode: certificate
elasticsearch.ssl.certificateAuthorities: ["/usr/share/kibana/config/certs/ca/ca.crt"]

# Authentication
elasticsearch.username: "kibana_system"
# Password provided via environment variable in docker-compose.yml

# Enable SSL for Kibana
server.ssl.enabled: true
server.ssl.certificate: "/usr/share/kibana/config/certs/instance/instance.crt"
server.ssl.key: "/usr/share/kibana/config/certs/instance/instance.key"

# Disable certain features to reduce load
xpack.observabilityAIAssistant.enabled: false
telemetry.enabled: false
EOF

# 3. Configure the system for Elasticsearch
echo "Setting vm.max_map_count for Elasticsearch..."
sudo sysctl -w vm.max_map_count=262144

# 4. Start Elasticsearch
echo "Starting Elasticsearch..."
docker compose up -d elasticsearch

# 5. Verify Elasticsearch startup
echo "Verifying that Elasticsearch is ready..."
max_attempts=30
attempt=1

while [ $attempt -le $max_attempts ]; do
  if curl -s -k -u elastic:4242 "https://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null; then
    echo "Elasticsearch is ready"
    break
  fi

  echo "Attempt $attempt/$max_attempts - Waiting for Elasticsearch to be ready..."
  attempt=$((attempt+1))
  sleep 5
done

if [ $attempt -gt $max_attempts ]; then
  echo "Error: Elasticsearch failed to start within the allotted time."
  docker logs elasticsearch
  exit 1
fi

# 6. Configure the kibana_system user
echo "Configuring kibana_system user..."
user_check=$(curl -s -k -u elastic:4242 "https://localhost:9200/_security/user/kibana_system")

if echo "$user_check" | grep -q '"kibana_system"'; then
  echo "User kibana_system exists, resetting password..."
  curl -s -k -X POST -u elastic:4242 "https://localhost:9200/_security/user/kibana_system/_password" \
    -H "Content-Type: application/json" \
    -d '{"password": "FB_2WU2-pAsFBRZGpncA"}'
else
  echo "User kibana_system not found, creating user..."
  curl -s -k -X POST -u elastic:4242 "https://localhost:9200/_security/user/kibana_system" \
    -H "Content-Type: application/json" \
    -d '{
      "password": "FB_2WU2-pAsFBRZGpncA",
      "roles": ["kibana_system"],
      "full_name": "Kibana System User",
      "email": "kibana@localhost"
    }'
fi

# 7. Start remaining services
echo "Starting remaining services..."
docker compose up -d

echo "ELK stack is now operational!"
echo "Kibana: https://localhost:5601"
echo "Elasticsearch: https://localhost:9200"
echo ""
echo "HTTPS is enabled; communications are secure."