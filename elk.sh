#!/bin/bash

set -e

ELK_MODE=${1:-"start"}
USE_SSL=${2:-"https"}

initialize_directories() {
    mkdir -p ./certs/ca ./certs/instance ./certs/shared
    mkdir -p ./ELK/elasticsearch/config ./ELK/kibana/config
    mkdir -p ./logs/auth ./logs/user ./logs/game ./logs/gateway
}

generate_certificates() {
    if [[ "$USE_SSL" != "https" ]]; then
        echo "Skipping certificate generation for HTTP mode"
        return
    fi

    echo "Generating certificates..."
    
    openssl genrsa -out ./certs/ca/ca.key 2048
    openssl req -new -x509 -sha256 -key ./certs/ca/ca.key -out ./certs/ca/ca.crt -days 3650 -subj "/C=FR/ST=Paris/L=Paris/O=ft_transcendance/CN=ft_transcendance-ca"

    openssl genrsa -out ./certs/instance/instance.key 2048
    openssl req -new -key ./certs/instance/instance.key -out ./certs/instance/instance.csr -subj "/C=FR/ST=Paris/L=Paris/O=ft_transcendance/CN=elasticsearch"
    openssl x509 -req -in ./certs/instance/instance.csr -CA ./certs/ca/ca.crt -CAkey ./certs/ca/ca.key -CAcreateserial -out ./certs/instance/instance.crt -days 365 -sha256


    cp ./certs/ca/ca.crt ./certs/shared/
    cp ./certs/instance/instance.crt ./certs/shared/
    cp ./certs/instance/instance.key ./certs/shared/
    
    rm -f ./certs/instance/instance.csr ./certs/ca/ca.srl

    chmod 644 ./certs/ca/ca.crt ./certs/instance/instance.crt ./certs/shared/*
    chmod 600 ./certs/ca/ca.key ./certs/instance/instance.key

    echo "Certificates generated successfully"
}

configure_elasticsearch() {
    local ssl_config=""
    
    if [[ "$USE_SSL" == "https" ]]; then
        ssl_config=$(cat <<EOF

xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.key: /usr/share/elasticsearch/config/certs/instance/instance.key
xpack.security.http.ssl.certificate: /usr/share/elasticsearch/config/certs/instance/instance.crt
xpack.security.http.ssl.certificate_authorities: [ "/usr/share/elasticsearch/config/certs/ca/ca.crt" ]
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.key: /usr/share/elasticsearch/config/certs/instance/instance.key
xpack.security.transport.ssl.certificate: /usr/share/elasticsearch/config/certs/instance/instance.crt
xpack.security.transport.ssl.certificate_authorities: [ "/usr/share/elasticsearch/config/certs/ca/ca.crt" ]
xpack.security.transport.ssl.verification_mode: certificate
EOF
)
    fi

    cat > ./ELK/elasticsearch/config/elasticsearch.yml <<EOF
cluster.name: "docker-cluster"
network.host: 0.0.0.0
discovery.type: single-node
xpack.security.enabled: true
xpack.security.authc.api_key.enabled: true$ssl_config

bootstrap.memory_lock: true
xpack.ml.enabled: false
xpack.watcher.enabled: false
EOF

    cat > ./ELK/elasticsearch/config/log4j2.properties <<EOF
status = error

appender.console.type = Console
appender.console.name = console
appender.console.layout.type = PatternLayout
appender.console.layout.pattern = [%d{ISO8601}][%-5p][%-25c{1.}] %marker%m%n

rootLogger.level = info
rootLogger.appenderRef.console.ref = console
EOF
}

configure_kibana() {
    local protocol="http"
    local ssl_config=""
    
    if [[ "$USE_SSL" == "https" ]]; then
        protocol="https"
        ssl_config=$(cat <<EOF

server.ssl.enabled: true
server.ssl.certificate: "/usr/share/kibana/config/certs/instance/instance.crt"
server.ssl.key: "/usr/share/kibana/config/certs/instance/instance.key"
elasticsearch.ssl.verificationMode: certificate
elasticsearch.ssl.certificateAuthorities: ["/usr/share/kibana/config/certs/ca/ca.crt"]
EOF
)
    fi

    cat > ./ELK/kibana/config/kibana.yml <<EOF
server.name: kibana
server.host: "0.0.0.0"

elasticsearch.hosts: ["$protocol://elasticsearch:9200"]
elasticsearch.username: "kibana_system"$ssl_config

# Disable certain features to reduce load
xpack.observabilityAIAssistant.enabled: false
telemetry.enabled: false
EOF
}

configure_logstash() {
    local es_ssl_config=""
    local protocol="http"
    
    if [[ "$USE_SSL" == "https" ]]; then
        protocol="https"
        es_ssl_config=$(cat <<EOF
xpack.monitoring.elasticsearch.ssl.certificate_authority: /usr/share/logstash/config/certs/ca/ca.crt
xpack.monitoring.elasticsearch.ssl.verification_mode: none
EOF
)
    fi

    cat > ./ELK/logstash/logstash.yml <<EOF
xpack.monitoring.enabled: true
xpack.monitoring.elasticsearch.hosts: ["$protocol://elasticsearch:9200"]
xpack.monitoring.elasticsearch.username: elastic
xpack.monitoring.elasticsearch.password: \${ELASTIC_PASSWORD}
$es_ssl_config
EOF

    local output_ssl_config=""
    
    if [[ "$USE_SSL" == "https" ]]; then
        output_ssl_config=$(cat <<EOF
        ssl => true
        ssl_certificate_verification => false
        cacert => "/usr/share/logstash/config/certs/ca/ca.crt"
EOF
)
    fi

    cat > ./ELK/logstash/logstash.conf <<EOF
input {
    file {
        path => "/var/log/app/**/*.log"
        start_position => "beginning"
        sincedb_path => "/dev/null"
        codec => "json"
        tags => ["backend_logs"]
    }
}

filter {
    if "backend_logs" in [tags] {
        date {
            match => ["timestamp", "ISO8601"]
        }
        
        grok {
            match => { "path" => "/var/log/app/(?<service>[^/]+)/.+" }
            tag_on_failure => ["_path_parse_failure"]
        }
        
        if ![service] {
            mutate {
                add_field => { "service" => "unknown" }
            }
        }
    }
}

output {
    elasticsearch {
        hosts => ["$protocol://elasticsearch:9200"]
        index => "ft_transcendance-logs-%{+YYYY.MM.dd}"
        user => "elastic"
        password => "\${ELASTIC_PASSWORD}"$output_ssl_config
    }
}
EOF
}

configure_environment() {
    local protocol="http"
    
    if [[ "$USE_SSL" == "https" ]]; then
        protocol="https"
    fi

    cat > ./.env <<EOF

ELASTIC_PASSWORD=4242
ELASTIC_PASSWORD=4242
KIBANA_SYSTEM_PASSWORD=FB_2WU2-pAsFBRZGpncA
KIBANA_ENCRYPTION_KEY=Y2xPTqoeUA0ZfrRf0JPzSeawnJVrJder
KIBANA_SECURITY_KEY=32charslongpaddedlavieestbeller32
KIBANA_REPORTING_KEY=32charslongpaddedlavieestbeller32
ELASTICSEARCH_HOSTS=$protocol://elasticsearch:9200
EOF

    # Update docker-compose.yml SSL settings
    if [[ "$USE_SSL" == "https" ]]; then
        sed -i 's/xpack.security.http.ssl.enabled: "false"/xpack.security.http.ssl.enabled: "true"/g' docker-compose.yml
        sed -i 's#http://localhost:9200#https://localhost:9200#g' docker-compose.yml
        sed -i 's/curl", "-f", "-u"/curl", "-f", "-k", "-u"/g' docker-compose.yml
    else
        sed -i 's/xpack.security.http.ssl.enabled: "true"/xpack.security.http.ssl.enabled: "false"/g' docker-compose.yml
        sed -i 's#https://localhost:9200#http://localhost:9200#g' docker-compose.yml
        sed -i 's/curl", "-f", "-k", "-u"/curl", "-f", "-u"/g' docker-compose.yml
    fi
}

configure_system() {
    echo "Setting vm.max_map_count for Elasticsearch..."
    sudo sysctl -w vm.max_map_count=262144
}

setup_users() {
    local protocol="http"
    local curl_opts=""
    
    if [[ "$USE_SSL" == "https" ]]; then
        protocol="https"
        curl_opts="--insecure"
    fi

    echo "Waiting for Elasticsearch to become ready..."
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl $curl_opts -s -u elastic:4242 "$protocol://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null; then
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
    echo "Checking for kibana_system user..."
    local user_check=$(docker exec elasticsearch curl $curl_opts -s -u elastic:4242 "$protocol://localhost:9200/_security/user/kibana_system")

    if echo "$user_check" | grep -q '"kibana_system"'; then
        echo "User kibana_system already exists, resetting password..."
        docker exec elasticsearch curl $curl_opts -s -X POST -u elastic:4242 \
            "$protocol://localhost:9200/_security/user/kibana_system/_password" \
            -H "Content-Type: application/json" \
            -d '{"password": "FB_2WU2-pAsFBRZGpncA"}'
    else
        echo "User kibana_system does not exist, creating user..."
        docker exec elasticsearch curl $curl_opts -s -X POST -u elastic:4242 \
            "$protocol://localhost:9200/_security/user/kibana_system" \
            -H "Content-Type: application/json" \
            -d '{
                "password": "FB_2WU2-pAsFBRZGpncA",
                "roles": ["kibana_system"],
                "full_name": "Kibana System User",
                "email": "kibana@localhost"
            }'
    fi
}

toggle_mode() {
    if [[ "$USE_SSL" == "https" ]]; then
        echo "Switching from HTTP to HTTPS mode..."
    else
        echo "Switching from HTTPS to HTTP mode..."
    fi
    
    docker compose down
    
    configure_elasticsearch
    configure_kibana
    configure_logstash
    configure_environment
    
    echo "Mode switched successfully. Starting services..."
    start_elk
}

start_elk() {
    echo "Starting ELK stack..."
    configure_system
    
    docker compose up -d elasticsearch
    
    setup_users
    
    docker compose up -d
    
    local protocol="http"
    if [[ "$USE_SSL" == "https" ]]; then
        protocol="https"
    fi
    
    echo "ELK stack started successfully!"
    echo "Elasticsearch: $protocol://localhost:9200"
    echo "Kibana: $protocol://localhost:5601"
    echo "Logstash is running and configured to collect logs"
}

stop_elk() {
    echo "Stopping ELK stack..."
    docker compose down
    echo "ELK stack stopped."
}

setup() {
    echo "Setting up ELK stack..."
    initialize_directories
    generate_certificates
    configure_elasticsearch
    configure_kibana
    configure_logstash
    configure_environment
    
    echo "ELK stack setup completed. Use './elk.sh start' to start the services."
}

case $ELK_MODE in
    "setup")
        setup
        ;;
    "start")
        start_elk
        ;;
    "stop")
        stop_elk
        ;;
    "toggle")
        toggle_mode
        ;;
    *)
        echo "Usage: ./elk.sh [setup|start|stop|toggle] [http|https]"
        echo "  setup  - Initializes directories and configurations"
        echo "  start  - Starts ELK stack services (default)"
        echo "  stop   - Stops ELK stack services"
        echo "  toggle - Switches between HTTP and HTTPS modes"
        echo ""
        echo "Second parameter for SSL mode:"
        echo "  http   - Use HTTP without SSL"
        echo "  https  - Use HTTPS with SSL (default)"
        ;;
esac
