import { useEffect, useState } from "react";
import { API_BASE } from "../api/client";

type PrivacyDoc = {
  title?: string;
  version?: string;
  body?: string;
  format?: string;
  source?: string;
};

function renderBody(doc: PrivacyDoc) {
  const body = (doc.body || "").trim();
  const format = (doc.format || "markdown").toLowerCase();
  if (!body) {
    return <p>Politique de confidentialité indisponible pour le moment.</p>;
  }
  if (format === "html") {
    return <div dangerouslySetInnerHTML={{ __html: body }} />;
  }
  // markdown / plain — keep newlines, light heading emphasis
  const blocks = body.split(/\n{2,}/);
  return (
    <>
      {blocks.map((block, i) => {
        const line = block.trim();
        if (!line) return null;
        if (line.startsWith("## ")) {
          return <h2 key={i}>{line.replace(/^##\s+/, "")}</h2>;
        }
        if (line.startsWith("# ")) {
          return <h2 key={i}>{line.replace(/^#\s+/, "")}</h2>;
        }
        if (line.startsWith("- ")) {
          const items = line.split(/\n/).filter((l) => l.trim().startsWith("- "));
          return (
            <ul key={i}>
              {items.map((item, j) => (
                <li key={j}>{item.replace(/^-\s+/, "").replace(/\*\*(.*?)\*\*/g, "$1")}</li>
              ))}
            </ul>
          );
        }
        return (
          <p key={i}>
            {line.split("\n").map((l, j) => (
              <span key={j}>
                {j > 0 && <br />}
                {l.replace(/\*\*(.*?)\*\*/g, "$1")}
              </span>
            ))}
          </p>
        );
      })}
    </>
  );
}

export default function PrivacyPage() {
  const [doc, setDoc] = useState<PrivacyDoc | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`${API_BASE}/legal/privacy`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const json = (await res.json()) as PrivacyDoc;
        if (!cancelled) setDoc(json);
      } catch (err) {
        if (!cancelled) {
          setError("Impossible de charger la politique depuis l’API — ouvrir la version HTML.");
          console.warn(err);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="legal-standalone">
      <header>
        <p className="legal-brand">SafeAlert — AfriSoft</p>
        <h1>{doc?.title || "Politique de confidentialité"}</h1>
        <p>
          {doc?.version ? `Version ${doc.version}` : "SafeAlert"}
          {doc?.source ? ` · source ${doc.source}` : ""}
        </p>
      </header>
      <article>
        {error && (
          <p>
            {error}{" "}
            <a href="/privacy.html">privacy.html</a>
          </p>
        )}
        {!doc && !error && <p>Chargement…</p>}
        {doc && renderBody(doc)}
        <p className="legal-links">
          <a href="/manuel">Manuel utilisateur</a>
          {" · "}
          <a href="/cgu">CGU</a>
          {" · "}
          <a href="/privacy.html">Version HTML</a>
          {" · "}
          <a href="/connexion">Connexion admin</a>
        </p>
      </article>
    </div>
  );
}
