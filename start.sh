#!/bin/bash

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
    echo "Environment variables loaded from .env"
else
    echo ".env file not found. Please ensure it exists."
    exit 1
fi

# Start ELK stack first using the centralized elk.sh script
echo "Starting ELK stack..."
./elk.sh start

# Start other application services
echo "Starting application services..."

docker compose up -d gateway auth user game frontend

echo "All services started successfully!"
echo "Gateway: http://localhost:9443"
echo "Frontend: http://localhost:443"
echo "Elasticsearch: https://localhost:9200"
echo "Kibana: https://localhost:5601"