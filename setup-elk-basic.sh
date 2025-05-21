#!/bin/bash

# Script for step-by-step ELK stack configuration
# 1. First configure without SSL
# 2. Then enable SSL once everything is working

echo "Step-by-step ELK stack configuration..."

# Stop all containers first
echo "Stopping containers..."
docker compose down

# Step 1: Configure without SSL
echo "Step 1: Configuring without SSL..."

echo "Updating configurations for HTTP..."

# elasticsearch.yml
cat > ./ELK/elasticsearch/config/elasticsearch.yml << EOF
cluster.name: "docker-cluster"
network.host: 0.0.0.0
discovery.type: single-node
xpack.security.enabled: true
xpack.security.authc.api_key.enabled: true

bootstrap.memory_lock: true
xpack.ml.enabled: false
xpack.watcher.enabled: false
EOF

# kibana.yml
cat > ./ELK/kibana/config/kibana.yml << EOF
server.name: kibana
server.host: "0.0.0.0"

elasticsearch.hosts: ["http://elasticsearch:9200"]
elasticsearch.username: "kibana_system"

# Disable SSL for Kibana
server.ssl.enabled: false

# Disable certain features to reduce load
xpack.observabilityAIAssistant.enabled: false
telemetry.enabled: false
EOF

# Update .env
echo "Generating .env for HTTP setup..."
cat > ./.env << EOF
# ELK stack environment variables

# Elasticsearch credentials
ELASTIC_PASSWORD=4242
KIBANA_SYSTEM_PASSWORD=FB_2WU2-pAsFBRZGpncA

# Kibana encryption keys
KIBANA_ENCRYPTION_KEY=Y2xPTqoeUA0ZfrRf0JPzSeawnJVrJder
KIBANA_SECURITY_KEY=32charslongpaddedlavieestbeller32
KIBANA_REPORTING_KEY=32charslongpaddedlavieestbeller32

# Elasticsearch configuration
ELASTICSEARCH_HOSTS=http://elasticsearch:9200
EOF

# Disable SSL flags in docker-compose.yml
echo "Disabling SSL settings in docker-compose..."
sed -i 's/xpack.security.http.ssl.enabled: "true"/xpack.security.http.ssl.enabled: "false"/g' docker-compose.yml
sed -i 's/https:\/\/localhost:9200/http:\/\/localhost:9200/g' docker-compose.yml
sed -i 's/curl", "-f", "-k", "-u"/curl", "-f", "-u"/g' docker-compose.yml

# Ensure vm.max_map_count is set for Elasticsearch
echo "Setting vm.max_map_count for Elasticsearch..."
sudo sysctl -w vm.max_map_count=262144

# Start Elasticsearch only
echo "Starting Elasticsearch..."
docker compose up -d elasticsearch

echo "Waiting for Elasticsearch to become ready..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s -u elastic:4242 "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null; then
        echo "Elasticsearch is ready"
        break
    fi
    echo "Attempt $attempt/$max_attempts - Elasticsearch not ready, retrying..."
    attempt=$((attempt+1))
    sleep 5
done

if [ $attempt -gt $max_attempts ]; then
    echo "Error: Elasticsearch failed to start properly."
    echo "Checking Elasticsearch logs..."
    docker logs elasticsearch
    exit 1
fi

# Configure kibana_system user
echo "Configuring kibana_system user..."
user_check=$(docker exec elasticsearch curl -s -u elastic:4242 "http://localhost:9200/_security/user/kibana_system")

if echo "$user_check" | grep -q '"kibana_system"'; then
  echo "User kibana_system already exists, resetting password..."
  docker exec elasticsearch curl -s -X POST -u elastic:4242 "http://localhost:9200/_security/user/kibana_system/_password" -H "Content-Type: application/json" -d '{"password": "FB_2WU2-pAsFBRZGpncA"}'
else
  echo "User kibana_system does not exist, creating user..."
  docker exec elasticsearch curl -s -X POST -u elastic:4242 "http://localhost:9200/_security/user/kibana_system" -H "Content-Type: application/json" -d '{
    "password": "FB_2WU2-pAsFBRZGpncA",
    "roles": ["kibana_system"],
    "full_name": "Kibana System User",
    "email": "kibana@localhost"
  }'
fi

# Start all other services
echo "Starting remaining services..."
docker compose up -d

echo "ELK stack is now configured without SSL."
echo "Once everything is verified, run the enable-elk-https.sh script to enable SSL."

# Generate the enable-elk-https.sh script for later use
echo "Creating enable-elk-https.sh for SSL activation..."
cat > ./enable-elk-https.sh << 'EOF'
#!/bin/bash

# Script to enable HTTPS on the ELK stack
echo "Enabling HTTPS for the ELK stack..."

# Stop containers
echo "Stopping containers..."
docker compose down

# Verify certificates
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

# Update configurations for HTTPS
echo "Updating configurations for HTTPS..."

# elasticsearch.yml
cat > ./ELK/elasticsearch/config/elasticsearch.yml << EOC
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
EOC

# kibana.yml
cat > ./ELK/kibana/config/kibana.yml << EOC
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
EOC

# Update .env for HTTPS
echo "Updating .env for HTTPS..."
cat > ./.env << EOC
# ELK stack environment variables

# Elasticsearch credentials
ELASTIC_PASSWORD=4242
KIBANA_SYSTEM_PASSWORD=FB_2WU2-pAsFBRZGpncA

# Kibana encryption keys
KIBANA_ENCRYPTION_KEY=Y2xPTqoeUA0ZfrRf0JPzSeawnJVrJder
KIBANA_SECURITY_KEY=32charslongpaddedlavieestbeller32
KIBANA_REPORTING_KEY=32charslongpaddedlavieestbeller32

# Elasticsearch configuration
ELASTICSEARCH_HOSTS=https://elasticsearch:9200
EOC

# Update docker-compose for HTTPS URLs
sed -i 's/xpack.security.http.ssl.enabled: "false"/xpack.security.http.ssl.enabled: "true"/g' docker-compose.yml
sed -i 's/http:\/\/localhost:9200/https:\/\/localhost:9200/g' docker-compose.yml
sed -i 's/curl", "-f", "-u"/curl", "-f", "-k", "-u"/g' docker-compose.yml

# Ensure vm.max_map_count is set for Elasticsearch
echo "Setting vm.max_map_count for Elasticsearch..."
sudo sysctl -w vm.max_map_count=262144

# Start all services with HTTPS enabled
echo "Starting services with HTTPS..."
docker compose up -d

echo "ELK stack is now configured with HTTPS!"
echo "Kibana: https://localhost:5601"
echo "Elasticsearch: https://localhost:9200"'

chmod +x ./enable-elk-https.sh