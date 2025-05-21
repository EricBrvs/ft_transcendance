# ft_transcendance

## Configuration de l'ELK Stack

### Configuration des variables d'environnement

Le projet utilise un fichier `.env` pour centraliser les mots de passe et les clés d'encryption. Ce fichier est nécessaire pour le bon fonctionnement de l'ELK Stack (Elasticsearch, Logstash, Kibana).

1. Assurez-vous que le fichier `.env` existe à la racine du projet avec les variables suivantes:

```properties
# ELK stack environment variables

# Elasticsearch credentials
ELASTIC_PASSWORD=<password_for_elastic_user>
KIBANA_SYSTEM_PASSWORD=<password_for_kibana_system_user>

# Kibana encryption keys
KIBANA_ENCRYPTION_KEY=<32_character_encryption_key>
KIBANA_SECURITY_KEY=<32_character_security_key>
KIBANA_REPORTING_KEY=<32_character_reporting_key>

# Elasticsearch configuration
ELASTICSEARCH_HOSTS=http://elasticsearch:9200
```

2. Personnalisez les mots de passe et clés d'encryption selon vos besoins. Les mots de passe par défaut sont:
   - `ELASTIC_PASSWORD`: 4242
   - `KIBANA_SYSTEM_PASSWORD`: FB_2WU2-pAsFBRZGpncA

### Démarrage des services

Pour démarrer les services:

```bash
./start.sh
```

Ce script va:
1. Charger les variables d'environnement depuis le fichier `.env`
2. Configurer le système pour Elasticsearch
3. Démarrer les conteneurs Docker
4. Créer/vérifier l'utilisateur `kibana_system` dans Elasticsearch

### Après une réinitialisation des volumes

Si vous avez exécuté `docker compose down -v` ou supprimé les volumes:

1. Exécutez simplement `./start.sh`
2. Le script détectera l'absence de l'utilisateur `kibana_system` et le recréera automatiquement

### Accès aux services

- Kibana: http://localhost:5601
- Elasticsearch: http://localhost:9200 (utilisateur: elastic, mot de passe: `ELASTIC_PASSWORD` défini dans .env)