GREEN = \033[0;32m
BLUE = \033[0;34m
YELLOW = \033[0;33m
RED = \033[0;31m
NC = \033[0m

ENV_FILE = .env
DOCKER_COMPOSE = docker compose

up: check_env
	@echo "$(BLUE)Démarrage des services...$(NC)"
	@./elk.sh start
	@$(DOCKER_COMPOSE) up -d gateway auth user game frontend
	@echo "$(GREEN)Tous les services ont démarré avec succès!$(NC)"
	@echo "$(GREEN)Gateway: http://localhost:9443$(NC)"
	@echo "$(GREEN)Frontend: http://localhost:443$(NC)"
	@echo "$(GREEN)Elasticsearch: https://localhost:9200$(NC)"
	@echo "$(GREEN)Kibana: https://localhost:5601$(NC)"

down:
	@echo "$(BLUE)Arrêt des services...$(NC)"
	@$(DOCKER_COMPOSE) down
	@echo "$(GREEN)Tous les services ont été arrêtés.$(NC)"

stop: down

restart: down up
	@echo "$(GREEN)Services redémarrés.$(NC)"

clean: down
	@echo "$(YELLOW)Suppression des volumes...$(NC)"
	@$(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)Nettoyage terminé.$(NC)"

fclean: clean
	@echo "$(YELLOW)Nettoyage complet...$(NC)"
	@docker system prune -af
	@echo "$(GREEN)Nettoyage complet terminé.$(NC)"

re: fclean up

.PHONY: all check_env config_system install up start run down stop restart logs service-logs status stats clean fclean re toggle http https help