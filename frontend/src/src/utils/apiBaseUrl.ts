export const getApiBaseUrl = (): string => {
    // Utiliser HTTPS avec le port configuré
    return `https://transcendence.com:${import.meta.env.VITE_BACKEND_PORT}`;
};
