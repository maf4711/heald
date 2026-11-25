// One JSON document in the private Vercel Blob store, with ETag-based
// optimistic concurrency (see blob-cas.ts). Shared by the fleet store and
// the device registry.

import { get, put, BlobError, BlobPreconditionFailedError } from "@vercel/blob";
import { parseDoc, type DocIO } from "./blob-cas";

/** Production must persist: no token there is a misconfiguration (→ 503), not memory-only. */
export function blobRequired(): boolean {
  return process.env.VERCEL_ENV === "production";
}

/** Blob-backed DocIO for `pathname`; null when BLOB_READ_WRITE_TOKEN is unset. */
export function blobJsonIO<T>(pathname: string): DocIO<T> | null {
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) return null;
  return {
    // abortSignal also stops the SDK's internal retries (VERCEL_BLOB_RETRIES)
    async read(ifNoneMatch, abortSignal) {
      const result = await get(pathname, {
        access: "private",
        token,
        useCache: false,
        abortSignal,
        ...(ifNoneMatch ? { ifNoneMatch } : {}),
      });
      if (!result) return null; // not found
      if (result.statusCode === 304) return { notModified: true, etag: result.blob.etag || ifNoneMatch };
      if (result.statusCode !== 200 || !result.stream) throw new Error("blob read failed");
      const text = await new Response(result.stream).text();
      return { snapshot: parseDoc(text) as T, etag: result.blob.etag || undefined };
    },
    async write(doc, etag, abortSignal) {
      const res = await put(pathname, JSON.stringify(doc), {
        access: "private",
        addRandomSuffix: false,
        token,
        contentType: "application/json",
        abortSignal,
        // Conditional overwrite, or create-only when no blob existed at read time
        ...(etag ? { allowOverwrite: true, ifMatch: etag } : { allowOverwrite: false }),
      });
      return res.etag;
    },
    isConflict(err) {
      if (err instanceof BlobPreconditionFailedError) return true; // ifMatch lost the race
      // Create-only put found the blob already there. @vercel/blob 2.6 maps this
      // to a plain BlobError (code "bad_request"; no subclass or code field), so
      // the SDK leaves the message as the only discriminator.
      return err instanceof BlobError && /already exists/i.test(err.message);
    },
  };
}
