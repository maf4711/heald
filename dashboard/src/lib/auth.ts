// API key validation (CLOUD-03).
// Keys are stored in HEALD_API_KEYS env var as comma-separated values.
// Example: HEALD_API_KEYS=key1,key2,key3

export function validateApiKey(request: Request): boolean {
  const authHeader = request.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) return false;

  const key = authHeader.slice(7);
  const validKeys = (process.env.HEALD_API_KEYS ?? "").split(",").filter(Boolean);

  // If no keys configured, reject all requests (fail-closed)
  if (validKeys.length === 0) return false;

  return validKeys.includes(key);
}
