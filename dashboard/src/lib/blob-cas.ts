// Compare-and-swap update of one remote JSON document (ETag optimistic
// concurrency). Pure: the blob transport is injected (blob-json.ts in prod,
// fake-blob.ts in tests). Shared by the fleet store and the device registry.

export type DocRead<T> = { snapshot: T; etag?: string; notModified?: false } | { notModified: true; etag?: string };

export interface DocIO<T> {
  /**
   * Current document + ETag, or null when it does not exist yet. With
   * `ifNoneMatch`, may answer `{ notModified: true }` when unchanged.
   */
  read(ifNoneMatch?: string, signal?: AbortSignal): Promise<DocRead<T> | null>;
  /**
   * Write `doc`. With `etag`: only if the remote still has that ETag. Without:
   * only if the document does not exist yet (create-only). Must throw an
   * error that `isConflict` recognises when the precondition fails. Returns
   * the new ETag when known.
   */
  write(doc: T, etag: string | undefined, signal?: AbortSignal): Promise<string | void>;
  isConflict(err: unknown): boolean;
}

/** The update did not land; the caller must not report success (ingest → 503). */
export class PersistError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = "PersistError";
  }
}

/**
 * Parse a stored JSON document. A corrupt or non-object document is logged
 * and treated as empty so one bad write cannot wedge every later request.
 */
export function parseDoc(text: string): Record<string, unknown> {
  if (!text) return {};
  try {
    const v: unknown = JSON.parse(text);
    if (typeof v === "object" && v !== null && !Array.isArray(v)) return v as Record<string, unknown>;
  } catch {
    /* fall through */
  }
  console.error(`blob document is not a JSON object (${text.length} bytes); treating it as empty`);
  return {};
}

export const MAX_CAS_ATTEMPTS = 6;
/** Total budget for one casUpdate (all attempts); the daemon times out at ~7 s. */
export const CAS_DEADLINE_MS = 5000;
/** Budget for a read-only refresh on the GET path. */
export const READ_DEADLINE_MS = 2500;

export interface CasOptions {
  attempts?: number;
  /** Abort every read/write/backoff after this many ms (whole update). */
  deadlineMs?: number;
  /** ETag the caller's local copy corresponds to: first read is conditional. */
  knownEtag?: string;
  /** Injected for tests; defaults to setTimeout. */
  sleep?: (ms: number) => Promise<void>;
}

const defaultSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** Jittered exponential backoff: ~25, 50, 100, 200 … ms (capped at 1 s). */
const backoffMs = (attempt: number) => Math.min(1000, 25 * 2 ** attempt) * (0.5 + Math.random());

/** Settle with `p`, or reject as soon as `signal` aborts (even if `p` never settles). */
export function untilAborted<R>(p: Promise<R>, signal: AbortSignal): Promise<R> {
  if (signal.aborted) return Promise.reject(signal.reason);
  return new Promise<R>((resolve, reject) => {
    const onAbort = () => reject(signal.reason);
    signal.addEventListener("abort", onAbort, { once: true });
    p.then(
      (v) => {
        signal.removeEventListener("abort", onAbort);
        resolve(v);
      },
      (e) => {
        signal.removeEventListener("abort", onAbort);
        reject(e);
      },
    );
  });
}

/** Run `fn` with an AbortSignal that fires after `ms`; rejects at the deadline at the latest. */
export async function withDeadline<R>(ms: number, fn: (signal: AbortSignal) => Promise<R>): Promise<R> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(new PersistError(`deadline of ${ms} ms exceeded`)), ms);
  try {
    return await untilAborted(fn(ctrl.signal), ctrl.signal);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Read → next(remote, unchanged) → conditional write, retried on ETag
 * conflicts within `deadlineMs`. `next` must merge idempotently (it may run
 * several times); `unchanged` is true when the conditional read on
 * `knownEtag` answered 304 (remote is then null: the caller's copy is
 * current). Resolves with the new ETag only once the write landed; throws
 * PersistError otherwise (error, missing ETag, deadline, retries used up).
 */
export async function casUpdate<T>(
  io: DocIO<T>,
  next: (remote: T | null, unchanged: boolean) => T,
  { attempts = MAX_CAS_ATTEMPTS, deadlineMs = CAS_DEADLINE_MS, knownEtag, sleep = defaultSleep }: CasOptions = {},
): Promise<string | undefined> {
  return withDeadline(deadlineMs, async (signal) => {
    const guard = <R>(p: Promise<R>, what: string) =>
      untilAborted(p, signal).catch((err: unknown) => {
        if (signal.aborted) throw signal.reason;
        if (err instanceof PersistError) throw err;
        throw new PersistError(`remote ${what} failed`, { cause: err });
      });
    for (let attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) await guard(sleep(backoffMs(attempt - 1)), "backoff");
      // Only the first read may be conditional: after a conflict our ETag is stale
      const ifNoneMatch = attempt === 0 ? knownEtag : undefined;
      const remote = await guard(io.read(ifNoneMatch, signal), "read");
      const unchanged = remote?.notModified === true;
      if (unchanged && !ifNoneMatch) throw new PersistError("unexpected not-modified read");
      const etag = unchanged ? remote.etag || ifNoneMatch : remote?.etag;
      // Never overwrite an existing doc unconditionally: that is a lost update.
      if (remote && !etag) throw new PersistError("remote document has no ETag");
      const doc = next(remote && !remote.notModified ? remote.snapshot : null, unchanged);
      try {
        return (await untilAborted(io.write(doc, etag, signal), signal)) || undefined;
      } catch (err) {
        if (signal.aborted) throw signal.reason;
        if (!io.isConflict(err)) throw new PersistError("remote write failed", { cause: err });
      }
    }
    throw new PersistError(`remote write conflicted ${attempts} times`);
  });
}
