// Cette fonction centralise la construction de l'URL du backend
export const getApiBaseUrl = (): string => {
	// Utiliser HTTPS avec le port configuré
	return `https://localhost:${import.meta.env.VITE_BACKEND_PORT}`;
};
