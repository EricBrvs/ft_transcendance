#!/bin/bash

set -e

echo "Configuring Elasticsearch with HTTPS..."

# 1. Stop all containers
echo "Stopping containers..."
docker compose down

# 2. Temporarily disable SSL in configuration
echo "Updating initial configuration..."

# Update elasticsearch.yml to disable SSL temporarily
cat > ./ELK/elasticsearch/config/elasticsearch.yml << EOF
cluster.name: "docker-cluster"
network.host: 0.0.0.0
discovery.type: single-node
xpack.security.enabled: true
xpack.security.authc.api_key.enabled: true

# SSL temporarily disabled
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false

bootstrap.memory_lock: true
xpack.ml.enabled: false
xpack.watcher.enabled: false
EOF

# Update docker-compose.yml to disable SSL flag
echo "Disabling SSL flag in docker-compose.yml..."
sed -i 's/xpack.security.http.ssl.enabled: "true"/xpack.security.http.ssl.enabled: "false"/g' docker-compose.yml

# Update healthcheck to use HTTP
echo "Updating healthcheck to use HTTP..."
sed -i 's#https://localhost:9200#http://localhost:9200#g' docker-compose.yml
sed -i 's/curl", "-f", "-k", "-u"/curl", "-f", "-u"/g' docker-compose.yml

# Update .env to use HTTP
echo "Updating .env for HTTP..."
sed -i 's|ELASTICSEARCH_HOSTS=https://elasticsearch:9200|ELASTICSEARCH_HOSTS=http://elasticsearch:9200|g' .env

# 3. Start Elasticsearch without SSL
echo "Starting Elasticsearch without SSL..."
docker compose up -d elasticsearch

# 4. Wait for Elasticsearch to be ready
echo "Waiting for Elasticsearch to become ready..."
while ! curl -s -u elastic:4242 "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null; do
    echo "Waiting for Elasticsearch..."
    sleep 5
done

echo "Elasticsearch is ready"

# 5. Generate certificates using elasticsearch-certutil
echo "Generating certificates with elasticsearch-certutil..."
docker exec elasticsearch bin/elasticsearch-certutil cert \
  --ca-cert /usr/share/elasticsearch/config/certs/ca/ca.crt \
  --ca-key /usr/share/elasticsearch/config/certs/ca/ca.key \
  --out /tmp/elastic-stack-certificates.p12 \
  --pass ""

# 6. Extract certificates and keys
echo "Extracting certificates from container..."
docker cp elasticsearch:/tmp/elastic-stack-certificates.p12 ./certs/

# Extract p12 content
mkdir -p ./certs/tmp
cd ./certs
openssl pkcs12 -in elastic-stack-certificates.p12 -out tmp/elastic-stack-ca.crt -nokeys -cacerts -passin pass:""
openssl pkcs12 -in elastic-stack-certificates.p12 -out tmp/elastic-stack-instance.crt -clcerts -nokeys -passin pass:""
openssl pkcs12 -in elastic-stack-certificates.p12 -out tmp/elastic-stack-instance.key -nocerts -nodes -passin pass:""

# Copy extracted files to proper locations
cp tmp/elastic-stack-ca.crt ca/ca.crt
cp tmp/elastic-stack-instance.crt instance/instance.crt
cp tmp/elastic-stack-instance.key instance/instance.key

# Clean up temporary files
rm -rf tmp elastic-stack-certificates.p12
cd ..

# 7. Stop Elasticsearch
echo "Stopping Elasticsearch..."
docker compose down

# 8. Update configuration to enable SSL
echo "Updating configuration to enable SSL..."

# Update elasticsearch.yml to enable SSL
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

# Update docker-compose.yml to enable SSL flag
echo "Enabling SSL flag in docker-compose.yml..."
sed -i 's/xpack.security.http.ssl.enabled: "false"/xpack.security.http.ssl.enabled: "true"/g' docker-compose.yml

# Update healthcheck to use HTTPS
echo "Updating healthcheck to use HTTPS..."
sed -i 's#http://localhost:9200#https://localhost:9200#g' docker-compose.yml
sed -i 's/curl", "-f", "-u"/curl", "-f", "-k", "-u"/g' docker-compose.yml

# Update .env to use HTTPS
echo "Updating .env for HTTPS..."
sed -i 's|ELASTICSEARCH_HOSTS=http://elasticsearch:9200|ELASTICSEARCH_HOSTS=https://elasticsearch:9200|g' .env

# 9. Start Elasticsearch with SSL
echo "Starting Elasticsearch with SSL..."
./start.sh

echo "Elasticsearch configuration with HTTPS completed!"
