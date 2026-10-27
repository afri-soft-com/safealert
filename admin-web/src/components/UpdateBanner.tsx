import { useCallback, useEffect, useState } from "react";
import { API_BASE } from "../api/client";

const DISMISS_KEY = "safealert_admin_update_dismissed";
const POLL_MS = 5 * 60 * 1000;

function compareVersions(a: string, b: string): number {
  const parts = (v: string) =>
    v.split(/[.+-]/).map((p) => {
      const n = Number.parseInt(p, 10);
      return Number.isFinite(n) ? n : 0;
    });
  const pa = parts(a);
  const pb = parts(b);
  const len = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i += 1) {
    const x = pa[i] ?? 0;
    const y = pb[i] ?? 0;
    if (x !== y) return x - y;
  }
  return 0;
}

function currentVersion(): string {
  return import.meta.env.VITE_APP_VERSION || "0.0.0";
}

function dismissedFor(version: string): boolean {
  try {
    return sessionStorage.getItem(DISMISS_KEY) === version;
  } catch {
    return false;
  }
}

function dismiss(version: string) {
  try {
    sessionStorage.setItem(DISMISS_KEY, version);
  } catch {
    /* ignore */
  }
}

function maxVersion(...versions: string[]): string | null {
  let best: string | null = null;
  for (const v of versions) {
    const t = v.trim();
    if (!t) continue;
    if (!best || compareVersions(best, t) < 0) best = t;
  }
  return best;
}

async function fetchRemoteVersion(): Promise<string | null> {
  const found: string[] = [];
  const stamp = Date.now();

  try {
    const res = await fetch(`${API_BASE}/app/version?t=${stamp}`, { cache: "no-store" });
    if (res.ok) {
      const body = (await res.json()) as { adminWebVersion?: string };
      if (body.adminWebVersion) found.push(body.adminWebVersion);
    }
  } catch {
    /* offline / CORS — try same-origin fallback */
  }

  // Fresh deploy fingerprint on the static host (survives SPA cache of old JS).
  try {
    const res = await fetch(`/version.json?t=${stamp}`, { cache: "no-store" });
    const ctype = res.headers.get("content-type") || "";
    if (res.ok && ctype.includes("json")) {
      const body = (await res.json()) as { version?: string };
      if (body.version) found.push(body.version);
    }
  } catch {
    /* ignore */
  }

  return maxVersion(...found);
}

export default function UpdateBanner() {
  const [latest, setLatest] = useState<string | null>(null);
  const [, setDismissTick] = useState(0);
  const local = currentVersion();

  const check = useCallback(async () => {
    // Missing inject → "0.0.0" would permanently show a false banner.
    if (!local || local === "0.0.0") {
      setLatest(null);
      return;
    }
    const remote = await fetchRemoteVersion();
    if (!remote) return;
    if (compareVersions(local, remote) < 0) {
      setLatest(remote);
    } else {
      setLatest(null);
    }
  }, [local]);

  useEffect(() => {
    void check();
    const id = window.setInterval(() => void check(), POLL_MS);
    const onFocus = () => void check();
    const onVisibility = () => {
      if (document.visibilityState === "visible") void check();
    };
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      window.clearInterval(id);
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [check]);

  if (!latest || dismissedFor(latest)) return null;

  return (
    <UpdateBannerBar
      latest={latest}
      local={local}
      onDismiss={() => {
        dismiss(latest);
        setDismissTick((n) => n + 1);
      }}
    />
  );
}

function UpdateBannerBar({
  latest,
  local,
  onDismiss,
}: {
  latest: string;
  local: string;
  onDismiss: () => void;
}) {
  useEffect(() => {
    document.body.classList.add("has-update-banner");
    return () => document.body.classList.remove("has-update-banner");
  }, []);

  return (
    <div className="update-banner" role="status">
      <div className="update-banner-copy">
        <strong>Nouvelle version disponible</strong>
        <span>
          La console SafeAlert {latest} est en ligne (vous êtes en {local}).
          Rechargez pour l’appliquer.
        </span>
      </div>
      <button type="button" className="update-banner-action" onClick={() => window.location.reload()}>
        Recharger
      </button>
      <button type="button" className="update-banner-dismiss" aria-label="Plus tard" onClick={onDismiss}>
        ×
      </button>
    </div>
  );
}
