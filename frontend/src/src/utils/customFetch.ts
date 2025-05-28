import { getApiBaseUrl } from "./apiBaseUrl";

export async function customFetch(
	url: string,
	options: RequestInit,
): Promise<Response> {
	if (url.startsWith("http://localhost")) {
		const path = new URL(url).pathname;
		url = `${getApiBaseUrl()}${path}`;
	}

	const fetchOptions = {
		...options,
	};

	const response = await fetch(url, fetchOptions);

	if (response.status === 401) {
		if (
			typeof window !== "undefined" &&
			window.location.pathname !== "/login"
		) {
			window.location.href = "/login";
		}
		throw new Error("Unauthorized");
	}

	return response;
}
