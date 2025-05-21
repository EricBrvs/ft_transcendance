#!/bin/bash

echo "Configuring ELK stack with HTTPS..."

# 1. Stop existing containers
echo "Stopping containers..."
docker compose down

# 2. Verify certificates
echo "Verifying certificates..."
if [ ! -f "./certs/ca/ca.crt" ] || [ ! -f "./certs/ca/ca.key" ] || [ ! -f "./certs/instance/instance.crt" ] || [ ! -f "./certs/instance/instance.key" ]; then
    echo "Error: Missing certificates!"
    echo "Please ensure the following files exist:"
    echo "- ./certs/ca/ca.crt"
    echo "- ./certs/ca/ca.key"
    echo "- ./certs/instance/instance.crt"
    echo "- ./certs/instance/instance.key"
    exit 1
fi

# 3. Adjust certificate permissions
echo "Adjusting certificate permissions..."
chmod 644 ./certs/ca/ca.crt ./certs/instance/instance.crt
chmod 600 ./certs/ca/ca.key ./certs/instance/instance.key

# 4. Create a temporary container to test certificate access
echo "Testing certificate access..."
docker run --rm -v "$(pwd)/certs:/certs" alpine:latest ls -la /certs/ca /certs/instance

# 5. Update configurations for HTTPS
echo "Updating configurations for HTTPS..."

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

# Encryption keys configured via environment variables
# - KIBANA_ENCRYPTION_KEY
# - KIBANA_SECURITY_KEY
# - KIBANA_REPORTING_KEY

# Disable certain features to reduce load
xpack.observabilityAIAssistant.enabled: false
telemetry.enabled: false
EOF

# Update environment file
echo "Updating .env file for HTTPS hosts..."
sed -i 's|ELASTICSEARCH_HOSTS=http://elasticsearch:9200|ELASTICSEARCH_HOSTS=https://elasticsearch:9200|g' .env

# 6. Start Elasticsearch only
echo "Starting Elasticsearch..."
docker compose up -d elasticsearch

# 7. Wait for Elasticsearch to be ready
echo "Waiting for Elasticsearch to become ready..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s -k -u elastic:4242 "https://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null; then
        echo "Elasticsearch is ready"
        break
    fi
    echo "Attempt $attempt/$max_attempts - Elasticsearch not ready yet, retrying..."
    attempt=$((attempt+1))
    sleep 5
done

if [ $attempt -gt $max_attempts ]; then
    echo "Error: Elasticsearch failed to start properly."
    echo "Checking Elasticsearch logs..."
    docker logs elasticsearch
    exit 1
fi

# 8. Configure kibana_system user
echo "Configuring kibana_system user..."
user_check=$(docker exec elasticsearch curl -s -k -u elastic:4242 "https://localhost:9200/_security/user/kibana_system")

if echo "$user_check" | grep -q '"kibana_system"'; then
  echo "User kibana_system already exists, resetting password..."
  docker exec elasticsearch curl -s -k -X POST -u elastic:4242 "https://localhost:9200/_security/user/kibana_system/_password" -H "Content-Type: application/json" -d '{"password": "FB_2WU2-pAsFBRZGpncA"}'
else
  echo "User kibana_system does not exist, creating user..."
  docker exec elasticsearch curl -s -k -X POST -u elastic:4242 "https://localhost:9200/_security/user/kibana_system" -H "Content-Type: application/json" -d '{
    "password": "FB_2WU2-pAsFBRZGpncA",
    "roles": ["kibana_system"],
    "full_name": "Kibana System User",
    "email": "kibana@localhost"
  }'
fi

# 9. Start remaining services
echo "Starting remaining services..."
docker compose up -d

echo "ELK stack is now configured with HTTPS!"
echo "Kibana: https://localhost:5601"
echo "Elasticsearch: https://localhost:9200"
