// Test double for one Vercel Blob JSON document: ETag bumps on every write,
// ifMatch / create-only enforced, If-None-Match answered with 304.
// Used by *.test.ts only (not imported by app code).

import { parseDoc, type DocIO } from "./blob-cas.ts";

export class Conflict extends Error {}
export class Unavailable extends Error {}

export const tick = () => new Promise((r) => setImmediate(r));
const never = () => new Promise<never>(() => {});

export class FakeBlob<T = unknown> {
  /** Raw stored text (may be set to corrupt JSON by tests). */
  doc: string | null = null;
  version = 0;
  reads = 0;
  notModified = 0;
  /** Writes that fail with a non-conflict error before succeeding again. */
  failWrites = 0;
  /** Writes that lose to a concurrent writer (precondition failed). */
  conflictWrites = 0;
  /** Writes / reads that never settle (ignore the abort signal). */
  hangWrites = 0;
  hangReads = 0;

  get etag() {
    return `e${this.version}`;
  }

  io(): DocIO<T> {
    return {
      read: async (ifNoneMatch) => {
        await tick();
        if (this.hangReads > 0) {
          this.hangReads--;
          return never();
        }
        this.reads++;
        if (this.doc === null) return null;
        if (ifNoneMatch && ifNoneMatch === this.etag) {
          this.notModified++;
          return { notModified: true, etag: this.etag };
        }
        return { snapshot: parseDoc(this.doc) as T, etag: this.etag };
      },
      write: async (doc, etag) => {
        await tick();
        if (this.hangWrites > 0) {
          this.hangWrites--;
          return never();
        }
        if (this.failWrites > 0) {
          this.failWrites--;
          throw new Unavailable("blob 503");
        }
        if (this.conflictWrites > 0) {
          this.conflictWrites--;
          this.version++; // someone else won the race
          throw new Conflict();
        }
        if (etag ? etag !== this.etag : this.doc !== null) throw new Conflict();
        this.doc = JSON.stringify(doc);
        this.version++;
        return this.etag;
      },
      isConflict: (e) => e instanceof Conflict,
    };
  }

  json(): T {
    return JSON.parse(this.doc ?? "null") as T;
  }
}
