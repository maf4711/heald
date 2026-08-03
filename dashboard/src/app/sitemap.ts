import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  return [
    {
      url: "https://heald.sh/",
      lastModified: now,
      changeFrequency: "daily",
      priority: 1,
    },
    {
      url: "https://heald.sh/api/update",
      lastModified: now,
      changeFrequency: "weekly",
      priority: 0.5,
    },
  ];
}
