import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: ["/", "/api/update", "/api/health"],
      disallow: ["/api/ingest", "/api/enroll", "/api/machines", "/api/events"],
    },
    sitemap: "https://heald.sh/sitemap.xml",
    host: "https://heald.sh",
  };
}
