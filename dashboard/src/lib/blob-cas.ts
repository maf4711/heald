// Compare-and-swap update of one remote JSON document (ETag optimistic
// concurrency). Pure: the blob transport is injected (blob-json.ts in prod,
// a fake in tests). Shared by the fleet store and the device registry.

export type DocRead<T> = { snapshot: T; etag?: string; notModified?: false } | { notModified: true; etag?: string };

export interface DocIO<T> {
  /**
   * Current document + ETag, or null when it does not exist yet. With
   * `ifNoneMatch`, may answer `{ notModified: true }` when unchanged.
   */
  read(ifNoneMatch?: string): Promise<DocRead<T> | null>;
  /**
   * Write `doc`. With `etag`: only if the remote still has that ETag. Without:
   * only if the document does not exist yet (create-only). Must throw an
   * error that `isConflict` recognises when the precondition fails. Returns
   * the new ETag when known.
   */
  write(doc: T, etag: string | undefined): Promise<string | void>;
  isConflict(err: unknown): boolean;
}

/** The update did not land; the caller must not report success (ingest → 503). */
export class PersistError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = "PersistError";
  }
}

export const MAX_CAS_ATTEMPTS = 6;

export interface CasOptions {
  attempts?: number;
  /** Injected for tests; defaults to setTimeout. */
  sleep?: (ms: number) => Promise<void>;
}

const defaultSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** Jittered exponential backoff: ~25, 50, 100, 200 … ms (capped at 1 s). */
const backoffMs = (attempt: number) => Math.min(1000, 25 * 2 ** attempt) * (0.5 + Math.random());

/**
 * Read → next(remote) → conditional write, retried on ETag conflicts.
 * `next` must merge idempotently into the remote doc (it may run several
 * times). Resolves with the new ETag only once the write has landed; throws
 * PersistError otherwise (non-conflict error, missing ETag, or retries used up).
 */
export async function casUpdate<T>(
  io: DocIO<T>,
  next: (remote: T | null) => T,
  { attempts = MAX_CAS_ATTEMPTS, sleep = defaultSleep }: CasOptions = {},
): Promise<string | undefined> {
  for (let attempt = 0; attempt < attempts; attempt++) {
    if (attempt > 0) await sleep(backoffMs(attempt - 1));
    let remote: DocRead<T> | null;
    try {
      remote = await io.read();
    } catch (err) {
      throw new PersistError("remote read failed", { cause: err });
    }
    if (remote?.notModified) throw new PersistError("unexpected not-modified read");
    // Never overwrite an existing doc unconditionally: that is a lost update.
    if (remote && !remote.etag) throw new PersistError("remote document has no ETag");
    const doc = next(remote ? remote.snapshot : null);
    try {
      return (await io.write(doc, remote?.etag)) || undefined;
    } catch (err) {
      if (!io.isConflict(err)) throw new PersistError("remote write failed", { cause: err });
    }
  }
  throw new PersistError(`remote write conflicted ${attempts} times`);
}
