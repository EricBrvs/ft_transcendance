#!/bin/bash

# Script to enable HTTPS on the ELK stack after verifying everything works

echo "Enabling HTTPS for the ELK stack..."

# 1. Stop all containers
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

# 3. Update configurations for HTTPS
echo "Updating configurations for HTTPS..."

# elasticsearch.yml
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

# kibana.yml
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

# Update docker-compose.yml to enable HTTPS flag
sed -i 's/xpack.security.http.ssl.enabled: "false"/xpack.security.http.ssl.enabled: "true"/g' docker-compose.yml

# Update .env file
echo "Updating .env with HTTPS settings..."
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
ELASTICSEARCH_HOSTS=https://elasticsearch:9200
EOF

# Update healthcheck URLs in docker-compose.yml to use HTTPS
sed -i 's#http://localhost:9200#https://localhost:9200#g' docker-compose.yml
sed -i 's#curl", "-f", "-u"#curl", "-f", "-k", "-u"#g' docker-compose.yml

# 4. Start all services with HTTPS enabled
echo "Starting services with HTTPS..."
docker compose up -d

echo "ELK stack is now configured with HTTPS!"
echo "Kibana: https://localhost:5601"
echo "Elasticsearch: https://localhost:9200"
echo ""
echo "Note: Services use self-signed certificates. You may need to"
echo "accept security warnings in your browser on first access."
