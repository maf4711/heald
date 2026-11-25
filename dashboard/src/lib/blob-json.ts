// One JSON document in the private Vercel Blob store, with ETag-based
// optimistic concurrency. Shared by the fleet store and the device registry.

import { get, put, BlobPreconditionFailedError } from "@vercel/blob";
import type { SnapshotIO } from "./store-snapshot";

/** Blob-backed SnapshotIO for `pathname`; null when BLOB_READ_WRITE_TOKEN is unset. */
export function blobJsonIO<T>(pathname: string): SnapshotIO<T> | null {
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) return null;
  return {
    async read() {
      const result = await get(pathname, { access: "private", token, useCache: false });
      if (!result) return null; // not found
      if (result.statusCode !== 200 || !result.stream) throw new Error("blob read failed");
      const text = await new Response(result.stream).text();
      return { snapshot: (text ? JSON.parse(text) : {}) as T, etag: result.blob.etag };
    },
    async write(doc, etag) {
      await put(pathname, JSON.stringify(doc), {
        access: "private",
        addRandomSuffix: false,
        allowOverwrite: true,
        token,
        contentType: "application/json",
        ...(etag ? { ifMatch: etag } : {}),
      });
    },
    isConflict(err) {
      return err instanceof BlobPreconditionFailedError;
    },
  };
}
