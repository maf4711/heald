// One JSON document in the private Vercel Blob store, with ETag-based
// optimistic concurrency (see blob-cas.ts). Shared by the fleet store and
// the device registry.

import { get, put, BlobPreconditionFailedError } from "@vercel/blob";
import type { DocIO } from "./blob-cas";

/** Blob-backed DocIO for `pathname`; null when BLOB_READ_WRITE_TOKEN is unset. */
export function blobJsonIO<T>(pathname: string): DocIO<T> | null {
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) return null;
  return {
    async read(ifNoneMatch) {
      const result = await get(pathname, {
        access: "private",
        token,
        useCache: false,
        ...(ifNoneMatch ? { ifNoneMatch } : {}),
      });
      if (!result) return null; // not found
      if (result.statusCode === 304) return { notModified: true, etag: result.blob.etag || ifNoneMatch };
      if (result.statusCode !== 200 || !result.stream) throw new Error("blob read failed");
      const text = await new Response(result.stream).text();
      return { snapshot: (text ? JSON.parse(text) : {}) as T, etag: result.blob.etag || undefined };
    },
    async write(doc, etag) {
      const res = await put(pathname, JSON.stringify(doc), {
        access: "private",
        addRandomSuffix: false,
        token,
        contentType: "application/json",
        // Conditional overwrite, or create-only when no blob existed at read time
        ...(etag ? { allowOverwrite: true, ifMatch: etag } : { allowOverwrite: false }),
      });
      return res.etag;
    },
    isConflict(err) {
      // ifMatch lost the race, or a create-only put found the blob already there
      return err instanceof BlobPreconditionFailedError || /already exists/i.test(String((err as Error)?.message));
    },
  };
}
