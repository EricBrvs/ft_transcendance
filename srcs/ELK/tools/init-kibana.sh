#!/bin/sh

echo "Attente que Elasticsearch soit disponible..."
until curl -s -f -o /dev/null "${ELASTICSEARCH_HOSTS}/_cluster/health?wait_for_status=yellow&timeout=50s"; do
    echo "En attente d'Elasticsearch..."
    sleep 5
done

echo "Elasticsearch est prêt!"

echo "Configuration initiale de Kibana terminée."

exit 0
