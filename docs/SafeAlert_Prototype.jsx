import { useState } from "react";

const COLORS = {
  rouge: "#CC1C1C",
  rougeDark: "#991515",
  rougeLight: "#FCEBEB",
  bleuFonce: "#0D1B2A",
  bleu: "#185FA5",
  gris: "#4A4A6A",
  grisClair: "#F5F5F7",
  orange: "#E86A1A",
  vert: "#3B6D11",
  vertClair: "#EAF3DE",
  blanc: "#FFFFFF",
};

const screens = ["brand", "splash", "home", "sos", "map", "contacts", "annuaire", "dashboard"];
const screenLabels = {
  brand: "Branding",
  splash: "Splash",
  home: "Accueil",
  sos: "SOS",
  map: "Carte",
  contacts: "Confiance",
  annuaire: "Annuaire",
  dashboard: "Stats",
};

const Phone = ({ children }) => (
  <div style={{
    width: 320,
    minHeight: 620,
    background: COLORS.bleuFonce,
    borderRadius: 40,
    padding: "12px 8px",
    boxShadow: "0 32px 80px rgba(0,0,0,0.35), 0 0 0 2px #1a2a3a",
    position: "relative",
    margin: "0 auto",
  }}>
    <div style={{
      background: COLORS.blanc,
      borderRadius: 32,
      overflow: "hidden",
      minHeight: 596,
      display: "flex",
      flexDirection: "column",
      position: "relative",
    }}>
      <div style={{
        background: COLORS.bleuFonce,
        height: 28,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        flexShrink: 0,
      }}>
        <div style={{ width: 80, height: 8, background: "#222", borderRadius: 4 }} />
      </div>
      <div style={{ flex: 1, overflow: "auto" }}>{children}</div>
    </div>
  </div>
);

const StatusBar = ({ dark }) => (
  <div style={{
    background: dark ? COLORS.bleuFonce : COLORS.rouge,
    color: "#fff",
    fontSize: 10,
    padding: "4px 16px",
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
  }}>
    <span style={{ fontWeight: 600 }}>9:41</span>
    <span>●●● WiFi 🔋</span>
  </div>
);

const TopBar = ({ title, dark, sub }) => (
  <div style={{
    background: dark ? COLORS.bleuFonce : COLORS.rouge,
    color: "#fff",
    padding: "10px 16px 12px",
  }}>
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <div style={{
        width: 28, height: 28,
        background: COLORS.rouge,
        borderRadius: 8,
        display: "flex", alignItems: "center", justifyContent: "center",
        fontSize: 14,
        border: "1.5px solid rgba(255,255,255,0.3)",
      }}>🛡</div>
      <div>
        <div style={{ fontWeight: 700, fontSize: 15, letterSpacing: 0.5 }}>SafeAlert</div>
        {sub && <div style={{ fontSize: 10, opacity: 0.75 }}>{sub}</div>}
      </div>
      <div style={{ marginLeft: "auto", fontSize: 18, cursor: "pointer" }}>☰</div>
    </div>
    {title && <div style={{ marginTop: 6, fontSize: 13, fontWeight: 600, opacity: 0.9 }}>{title}</div>}
  </div>
);

const NavBar = ({ active, setScreen }) => {
  const items = [
    { id: "home", icon: "🏠", label: "Accueil" },
    { id: "map", icon: "🗺", label: "Carte" },
    { id: "contacts", icon: "👥", label: "Confiance" },
    { id: "annuaire", icon: "📞", label: "Urgences" },
    { id: "dashboard", icon: "📊", label: "Stats" },
  ];
  return (
    <div style={{
      display: "flex",
      background: COLORS.blanc,
      borderTop: `1px solid #eee`,
      padding: "6px 0 4px",
      flexShrink: 0,
    }}>
      {items.map(item => (
        <button key={item.id} onClick={() => setScreen(item.id)} style={{
          flex: 1, border: "none", background: "none", cursor: "pointer",
          display: "flex", flexDirection: "column", alignItems: "center", gap: 2,
          padding: "2px 0",
          color: active === item.id ? COLORS.rouge : "#aaa",
          fontSize: 10,
          fontWeight: active === item.id ? 700 : 400,
        }}>
          <span style={{ fontSize: 16 }}>{item.icon}</span>
          <span>{item.label}</span>
        </button>
      ))}
    </div>
  );
};

const BrandScreen = () => (
  <div style={{ background: COLORS.blanc, minHeight: 600 }}>
    <div style={{
      background: COLORS.bleuFonce,
      padding: "40px 24px 32px",
      textAlign: "center",
    }}>
      <div style={{
        width: 80, height: 80,
        background: COLORS.rouge,
        borderRadius: 20,
        display: "flex", alignItems: "center", justifyContent: "center",
        fontSize: 40,
        margin: "0 auto 16px",
        boxShadow: "0 8px 24px rgba(204,28,28,0.4)",
      }}>🛡</div>
      <div style={{ color: "#fff", fontSize: 28, fontWeight: 800, letterSpacing: 1 }}>SafeAlert</div>
      <div style={{ color: "rgba(255,255,255,0.55)", fontSize: 12, marginTop: 4, letterSpacing: 2 }}>SÉCURITÉ CITOYENNE</div>
    </div>
    <div style={{ padding: "24px 20px" }}>
      <div style={{ fontSize: 11, color: COLORS.rouge, fontWeight: 700, letterSpacing: 2, marginBottom: 12 }}>IDENTITÉ VISUELLE</div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginBottom: 20 }}>
        {[
          { bg: COLORS.bleuFonce, label: "Bleu Nuit", hex: "#0D1B2A", text: "#fff" },
          { bg: COLORS.rouge, label: "Rouge Alerte", hex: "#CC1C1C", text: "#fff" },
          { bg: COLORS.orange, label: "Orange Vigilance", hex: "#E86A1A", text: "#fff" },
          { bg: "#F5F5F7", label: "Gris Clair", hex: "#F5F5F7", text: COLORS.bleuFonce },
        ].map(c => (
          <div key={c.hex} style={{
            background: c.bg, borderRadius: 10, padding: "10px 12px",
            border: c.bg === "#F5F5F7" ? "1px solid #ddd" : "none",
          }}>
            <div style={{ fontSize: 13, fontWeight: 700, color: c.text }}>{c.label}</div>
            <div style={{ fontSize: 10, color: c.text, opacity: 0.7, marginTop: 2 }}>{c.hex}</div>
          </div>
        ))}
      </div>
      <div style={{ fontSize: 11, color: COLORS.rouge, fontWeight: 700, letterSpacing: 2, marginBottom: 12 }}>TYPOGRAPHIE</div>
      <div style={{ background: COLORS.grisClair, borderRadius: 10, padding: 14, marginBottom: 16 }}>
        <div style={{ fontSize: 20, fontWeight: 800, color: COLORS.bleuFonce, fontFamily: "Georgia, serif" }}>SafeAlert</div>
        <div style={{ fontSize: 11, color: COLORS.gris, marginTop: 2 }}>Titre — Georgia Bold 800</div>
        <div style={{ fontSize: 14, fontWeight: 600, color: COLORS.bleuFonce, marginTop: 8 }}>Protéger. Alerter. Unir.</div>
        <div style={{ fontSize: 11, color: COLORS.gris, marginTop: 2 }}>Sous-titre — Sans-serif 600</div>
        <div style={{ fontSize: 12, color: COLORS.gris, marginTop: 8, lineHeight: 1.5 }}>Corps de texte standard utilisé pour les messages et descriptions dans l'application.</div>
        <div style={{ fontSize: 11, color: COLORS.gris, marginTop: 2 }}>Corps — Sans-serif 400</div>
      </div>
      <div style={{ fontSize: 11, color: COLORS.rouge, fontWeight: 700, letterSpacing: 2, marginBottom: 12 }}>ICÔNES & BADGES</div>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        {[
          { icon: "🆘", label: "SOS", bg: COLORS.rouge },
          { icon: "⚠️", label: "Alerte", bg: COLORS.orange },
          { icon: "📍", label: "Signalement", bg: COLORS.bleu },
          { icon: "✅", label: "Zone sûre", bg: COLORS.vert },
        ].map(b => (
          <div key={b.label} style={{
            background: b.bg, borderRadius: 20, padding: "6px 12px",
            display: "flex", alignItems: "center", gap: 5, color: "#fff",
          }}>
            <span style={{ fontSize: 13 }}>{b.icon}</span>
            <span style={{ fontSize: 11, fontWeight: 600 }}>{b.label}</span>
          </div>
        ))}
      </div>
    </div>
  </div>
);

const SplashScreen = ({ setScreen }) => (
  <div style={{
    background: COLORS.bleuFonce,
    minHeight: 596,
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    padding: 32,
    textAlign: "center",
  }}>
    <div style={{
      width: 100, height: 100,
      background: COLORS.rouge,
      borderRadius: 28,
      display: "flex", alignItems: "center", justifyContent: "center",
      fontSize: 50,
      marginBottom: 24,
      boxShadow: "0 0 0 12px rgba(204,28,28,0.15), 0 0 0 24px rgba(204,28,28,0.07)",
    }}>🛡</div>
    <div style={{ color: "#fff", fontSize: 32, fontWeight: 800, letterSpacing: 1, marginBottom: 4 }}>SafeAlert</div>
    <div style={{ color: "rgba(255,255,255,0.5)", fontSize: 12, letterSpacing: 3, marginBottom: 40 }}>SÉCURITÉ CITOYENNE</div>
    <div style={{ color: "rgba(255,255,255,0.7)", fontSize: 13, lineHeight: 1.6, marginBottom: 48, maxWidth: 240 }}>
      Alertez votre communauté. Restez en sécurité. Ensemble.
    </div>
    <button onClick={() => setScreen("home")} style={{
      background: COLORS.rouge,
      color: "#fff",
      border: "none",
      borderRadius: 16,
      padding: "14px 40px",
      fontSize: 15,
      fontWeight: 700,
      cursor: "pointer",
      width: "100%",
      marginBottom: 12,
    }}>Commencer</button>
    <button style={{
      background: "transparent",
      color: "rgba(255,255,255,0.6)",
      border: "1px solid rgba(255,255,255,0.2)",
      borderRadius: 16,
      padding: "14px 40px",
      fontSize: 15,
      fontWeight: 600,
      cursor: "pointer",
      width: "100%",
    }}>Se connecter</button>
    <div style={{ color: "rgba(255,255,255,0.3)", fontSize: 10, marginTop: 32 }}>
      Vos données sont protégées et anonymisées
    </div>
  </div>
);

const HomeScreen = ({ setScreen }) => {
  const [alertSent, setAlertSent] = useState(false);
  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: 568, background: "#f8f8f8" }}>
      <StatusBar />
      <TopBar sub="Bonjour, Citoyen 👋" />
      <div style={{ flex: 1, padding: "16px 14px 8px", overflow: "auto" }}>
        <div style={{
          background: COLORS.rougeLight,
          border: `1.5px solid ${COLORS.rouge}`,
          borderRadius: 12,
          padding: "10px 14px",
          marginBottom: 14,
          display: "flex",
          alignItems: "center",
          gap: 10,
        }}>
          <span style={{ fontSize: 20 }}>⚠️</span>
          <div>
            <div style={{ fontSize: 12, fontWeight: 700, color: COLORS.rouge }}>Alerte active — Secteur B</div>
            <div style={{ fontSize: 11, color: COLORS.gris }}>Vol signalé il y a 12 min à 300m</div>
          </div>
        </div>
        <button onClick={() => { setAlertSent(true); setTimeout(() => setAlertSent(false), 3000); setScreen("sos"); }}
          style={{
            width: "100%",
            background: alertSent ? "#991515" : COLORS.rouge,
            color: "#fff",
            border: "none",
            borderRadius: 20,
            padding: "22px 0",
            fontSize: 18,
            fontWeight: 800,
            cursor: "pointer",
            marginBottom: 14,
            boxShadow: alertSent ? "0 0 0 8px rgba(204,28,28,0.25)" : "0 4px 20px rgba(204,28,28,0.3)",
            transition: "all 0.2s",
            letterSpacing: 1,
          }}>
          {alertSent ? "✅ ALERTE ENVOYÉE !" : "🆘  BOUTON SOS"}
        </button>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginBottom: 14 }}>
          {[
            { icon: "🗺", label: "Carte des zones", sub: "3 alertes actives", screen: "map", accent: COLORS.bleu },
            { icon: "👥", label: "Mes contacts", sub: "5 personnes de confiance", screen: "contacts", accent: COLORS.vert },
            { icon: "📞", label: "Urgences", sub: "Accès hors-ligne", screen: "annuaire", accent: COLORS.orange },
            { icon: "📊", label: "Statistiques", sub: "Votre quartier", screen: "dashboard", accent: COLORS.gris },
          ].map(item => (
            <button key={item.label} onClick={() => setScreen(item.screen)} style={{
              background: COLORS.blanc,
              border: `1px solid #eee`,
              borderRadius: 12,
              padding: "12px 10px",
              cursor: "pointer",
              textAlign: "left",
            }}>
              <div style={{ fontSize: 22, marginBottom: 4 }}>{item.icon}</div>
              <div style={{ fontSize: 12, fontWeight: 700, color: COLORS.bleuFonce }}>{item.label}</div>
              <div style={{ fontSize: 10, color: COLORS.gris, marginTop: 2 }}>{item.sub}</div>
            </button>
          ))}
        </div>
        <div style={{ background: COLORS.blanc, borderRadius: 12, padding: "12px 14px", border: "1px solid #eee" }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.rouge, marginBottom: 8, letterSpacing: 1 }}>ACTIVITÉ RÉCENTE</div>
          {[
            { icon: "🟡", text: "Présence suspecte — Rue Kasa-Vubu", time: "18 min" },
            { icon: "🔴", text: "Agression signalée — Marché central", time: "1h" },
            { icon: "🟢", text: "Zone sécurisée — Av. de l'Indép.", time: "2h" },
          ].map((a, i) => (
            <div key={i} style={{
              display: "flex", alignItems: "flex-start", gap: 8,
              paddingBottom: 8, marginBottom: 8,
              borderBottom: i < 2 ? "1px solid #f0f0f0" : "none",
            }}>
              <span style={{ fontSize: 12, marginTop: 1 }}>{a.icon}</span>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 11, color: COLORS.bleuFonce, fontWeight: 500 }}>{a.text}</div>
                <div style={{ fontSize: 10, color: COLORS.gris }}>Il y a {a.time}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
      <NavBar active="home" setScreen={setScreen} />
    </div>
  );
};

const SOSScreen = ({ setScreen }) => {
  const [step, setStep] = useState(0);
  const steps = [
    { icon: "📍", label: "GPS localisé", color: COLORS.vert },
    { icon: "📲", label: "Contacts alertés", color: COLORS.vert },
    { icon: "📡", label: "Communauté notifiée", color: COLORS.vert },
    { icon: "🚨", label: "Alerte transmise !", color: COLORS.rouge },
  ];
  const sendSOS = () => {
    let i = 0;
    setStep(1);
    const interval = setInterval(() => {
      i++;
      setStep(i + 1);
      if (i >= 3) clearInterval(interval);
    }, 800);
  };
  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: 568, background: step > 3 ? COLORS.rougeLight : "#fff" }}>
      <StatusBar />
      <div style={{ background: COLORS.rouge, padding: "12px 16px 16px", textAlign: "center" }}>
        <div style={{ color: "rgba(255,255,255,0.7)", fontSize: 11, letterSpacing: 2 }}>ALERTE D'URGENCE</div>
        <div style={{ color: "#fff", fontSize: 16, fontWeight: 700 }}>Bouton SOS</div>
      </div>
      <div style={{ flex: 1, padding: 20, display: "flex", flexDirection: "column", alignItems: "center" }}>
        <button onClick={sendSOS} style={{
          width: 160, height: 160,
          borderRadius: "50%",
          background: step > 0 ? "#991515" : COLORS.rouge,
          color: "#fff",
          fontSize: 18,
          fontWeight: 800,
          border: "none",
          cursor: "pointer",
          margin: "20px 0",
          boxShadow: step > 0
            ? "0 0 0 16px rgba(204,28,28,0.2), 0 0 0 32px rgba(204,28,28,0.1)"
            : "0 0 0 12px rgba(204,28,28,0.15)",
          transition: "all 0.3s",
          letterSpacing: 1,
        }}>
          {step === 0 ? "🆘\nAPPUYER" : step > 3 ? "✅\nENVOYÉ !" : "⏳\nEnvoi..."}
        </button>
        <div style={{ width: "100%", marginBottom: 16 }}>
          {steps.map((s, i) => (
            <div key={i} style={{
              display: "flex", alignItems: "center", gap: 12,
              padding: "8px 12px",
              background: step > i ? `${s.color}15` : "#f8f8f8",
              borderRadius: 10,
              marginBottom: 6,
              border: `1px solid ${step > i ? s.color : "#eee"}`,
              transition: "all 0.3s",
            }}>
              <span style={{ fontSize: 18 }}>{step > i ? "✅" : s.icon}</span>
              <span style={{ fontSize: 12, fontWeight: 600, color: step > i ? s.color : COLORS.gris }}>{s.label}</span>
            </div>
          ))}
        </div>
        <div style={{
          background: COLORS.grisClair, borderRadius: 12, padding: "10px 14px",
          width: "100%", marginBottom: 14,
        }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.bleuFonce, marginBottom: 6 }}>MODE DISCRET</div>
          <div style={{ fontSize: 11, color: COLORS.gris }}>Pour déclencher sans afficher l'app :</div>
          <div style={{ fontSize: 11, fontWeight: 600, color: COLORS.rouge, marginTop: 4 }}>
            Appuyer 3× sur le bouton Volume ↓
          </div>
        </div>
        <button onClick={() => setScreen("home")} style={{
          background: "transparent", color: COLORS.gris, border: `1px solid #ddd`,
          borderRadius: 10, padding: "10px 0", fontSize: 12, cursor: "pointer", width: "100%",
        }}>← Retour à l'accueil</button>
      </div>
    </div>
  );
};

const MapScreen = ({ setScreen }) => {
  const [selected, setSelected] = useState(null);
  const incidents = [
    { id: 1, x: 90, y: 120, color: COLORS.rouge, icon: "🔴", type: "Agression", zone: "Marché central", time: "12 min" },
    { id: 2, x: 200, y: 80, color: COLORS.orange, icon: "🟡", type: "Suspect", zone: "Rue Kasa-Vubu", time: "28 min" },
    { id: 3, x: 150, y: 180, color: COLORS.orange, icon: "🟡", type: "Vol", zone: "Av. Lumumba", time: "45 min" },
    { id: 4, x: 240, y: 160, color: COLORS.vert, icon: "🟢", type: "Zone sûre", zone: "École centrale", time: "2h" },
  ];
  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: 568, background: "#fff" }}>
      <StatusBar />
      <TopBar title="Carte des incidents" />
      <div style={{ flex: 1, overflow: "auto", padding: "12px 14px" }}>
        <div style={{ display: "flex", gap: 6, marginBottom: 10 }}>
          {[
            { color: COLORS.rouge, label: "Danger" },
            { color: COLORS.orange, label: "Vigilance" },
            { color: COLORS.vert, label: "Sûr" },
          ].map(b => (
            <div key={b.label} style={{
              background: `${b.color}20`, border: `1px solid ${b.color}`,
              borderRadius: 20, padding: "3px 10px", fontSize: 10, fontWeight: 600, color: b.color,
            }}>{b.label}</div>
          ))}
          <div style={{ marginLeft: "auto", fontSize: 10, color: COLORS.gris, alignSelf: "center" }}>3 alertes actives</div>
        </div>
        <div style={{
          background: "#E8F0EE",
          borderRadius: 14,
          height: 260,
          position: "relative",
          overflow: "hidden",
          border: "1px solid #ccc",
          marginBottom: 14,
        }}>
          {[
            { x: 10, y: 20, w: 130, h: 40, label: "Marché central", dark: true },
            { x: 160, y: 10, w: 120, h: 50, label: "Zone résidentielle" },
            { x: 10, y: 80, w: 90, h: 80, label: "Secteur A" },
            { x: 110, y: 90, w: 80, h: 60, label: "Secteur B", dark: true },
            { x: 200, y: 80, w: 90, h: 80, label: "Secteur C" },
          ].map((z, i) => (
            <div key={i} style={{
              position: "absolute", left: z.x, top: z.y, width: z.w, height: z.h,
              background: z.dark ? "rgba(0,0,0,0.08)" : "rgba(255,255,255,0.4)",
              border: "1px solid rgba(0,0,0,0.1)",
              borderRadius: 4,
              display: "flex", alignItems: "center", justifyContent: "center",
              fontSize: 8, color: "rgba(0,0,0,0.4)",
            }}>{z.label}</div>
          ))}
          {incidents.map(inc => (
            <button key={inc.id} onClick={() => setSelected(selected?.id === inc.id ? null : inc)} style={{
              position: "absolute", left: inc.x - 14, top: inc.y - 14,
              width: 28, height: 28, borderRadius: "50%",
              background: inc.color,
              border: selected?.id === inc.id ? "3px solid #fff" : "2px solid #fff",
              boxShadow: `0 0 0 ${selected?.id === inc.id ? 3 : 0}px ${inc.color}`,
              cursor: "pointer",
              fontSize: 12,
              display: "flex", alignItems: "center", justifyContent: "center",
              transition: "all 0.2s",
            }}>
              {inc.id}
            </button>
          ))}
          <div style={{
            position: "absolute", bottom: 8, left: "50%", transform: "translateX(-50%)",
            background: "rgba(0,0,0,0.5)", color: "#fff", fontSize: 9, borderRadius: 10,
            padding: "2px 8px",
          }}>OpenStreetMap © — Données communautaires</div>
        </div>
        {selected ? (
          <div style={{
            background: `${selected.color}15`,
            border: `1.5px solid ${selected.color}`,
            borderRadius: 12, padding: "12px 14px", marginBottom: 10,
          }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
              <div>
                <div style={{ fontSize: 13, fontWeight: 700, color: selected.color }}>{selected.type}</div>
                <div style={{ fontSize: 11, color: COLORS.gris }}>{selected.zone}</div>
                <div style={{ fontSize: 10, color: COLORS.gris, marginTop: 2 }}>Signalé il y a {selected.time}</div>
              </div>
              <button onClick={() => setSelected(null)} style={{
                background: "none", border: "none", fontSize: 16, cursor: "pointer", color: COLORS.gris,
              }}>✕</button>
            </div>
          </div>
        ) : (
          <div style={{ fontSize: 11, color: COLORS.gris, textAlign: "center", marginBottom: 10 }}>
            Touchez un marqueur pour voir les détails
          </div>
        )}
        <button style={{
          width: "100%", background: COLORS.rouge, color: "#fff", border: "none",
          borderRadius: 12, padding: "12px 0", fontSize: 13, fontWeight: 700, cursor: "pointer",
        }}>📍 Signaler un incident ici</button>
      </div>
      <NavBar active="map" setScreen={setScreen} />
    </div>
  );
};

const ContactsScreen = ({ setScreen }) => {
  const contacts = [
    { initials: "MK", name: "Marie Kabila", role: "Voisine — Appt 12", status: "online", color: "#185FA5" },
    { initials: "JL", name: "Jean Lumumba", role: "Frère — Famille", status: "online", color: "#3B6D11" },
    { initials: "FT", name: "Fatou Traoré", role: "Amie — Quartier", status: "offline", color: "#E86A1A" },
    { initials: "PM", name: "Pierre Mwamba", role: "Chef de quartier", status: "online", color: "#993556" },
  ];
  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: 568, background: "#fff" }}>
      <StatusBar />
      <TopBar title="Cercle de confiance" />
      <div style={{ flex: 1, padding: "14px 14px 8px", overflow: "auto" }}>
        <div style={{
          background: COLORS.vertClair,
          border: `1px solid ${COLORS.vert}`,
          borderRadius: 10, padding: "8px 12px", marginBottom: 14,
          fontSize: 11, color: COLORS.vert, fontWeight: 600,
        }}>✅ 3 contacts en ligne — Ils seront alertés en cas de SOS</div>
        {contacts.map((c, i) => (
          <div key={i} style={{
            display: "flex", alignItems: "center", gap: 12, padding: "10px 0",
            borderBottom: i < contacts.length - 1 ? "1px solid #f0f0f0" : "none",
          }}>
            <div style={{
              width: 42, height: 42, borderRadius: "50%",
              background: c.color,
              display: "flex", alignItems: "center", justifyContent: "center",
              fontSize: 14, fontWeight: 700, color: "#fff", flexShrink: 0,
              position: "relative",
            }}>
              {c.initials}
              <div style={{
                position: "absolute", bottom: 0, right: 0,
                width: 11, height: 11, borderRadius: "50%",
                background: c.status === "online" ? COLORS.vert : "#ccc",
                border: "2px solid #fff",
              }} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 600, color: COLORS.bleuFonce }}>{c.name}</div>
              <div style={{ fontSize: 10, color: COLORS.gris }}>{c.role}</div>
            </div>
            <button style={{
              background: COLORS.grisClair, border: "none", borderRadius: 8,
              padding: "6px 10px", fontSize: 11, color: COLORS.gris, cursor: "pointer",
            }}>📲</button>
          </div>
        ))}
        <button style={{
          width: "100%", background: COLORS.bleuFonce, color: "#fff", border: "none",
          borderRadius: 12, padding: "12px 0", fontSize: 13, fontWeight: 700, cursor: "pointer",
          marginTop: 14,
        }}>+ Ajouter un contact de confiance</button>
      </div>
      <NavBar active="contacts" setScreen={setScreen} />
    </div>
  );
};

const AnnuaireScreen = ({ setScreen }) => {
  const services = [
    { icon: "🚔", name: "Police nationale", num: "112", sub: "Disponible 24h/24", color: COLORS.bleu },
    { icon: "🏥", name: "Hôpital général", num: "15", sub: "Urgences médicales", color: COLORS.rouge },
    { icon: "🚒", name: "Pompiers", num: "118", sub: "Incendie & secours", color: COLORS.orange },
    { icon: "👮", name: "Gendarmerie locale", num: "+243 XX XXX", sub: "Commissariat central", color: COLORS.gris },
    { icon: "🏛", name: "Chef de quartier", num: "+243 XX XXX", sub: "Mairie — Secteur B", color: COLORS.vert },
  ];
  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: 568, background: "#fff" }}>
      <StatusBar />
      <TopBar title="Annuaire d'urgence" />
      <div style={{ flex: 1, padding: "12px 14px 8px", overflow: "auto" }}>
        <div style={{
          background: "#fff3cd", border: "1px solid #E86A1A",
          borderRadius: 10, padding: "8px 12px", marginBottom: 14,
          fontSize: 11, color: "#7a4f00",
        }}>📶 Mode hors-ligne disponible — Données sauvegardées localement</div>
        {services.map((s, i) => (
          <div key={i} style={{
            display: "flex", alignItems: "center", gap: 12,
            background: COLORS.blanc,
            border: "1px solid #eee",
            borderRadius: 12, padding: "12px 14px", marginBottom: 8,
          }}>
            <div style={{
              width: 44, height: 44, borderRadius: 12,
              background: `${s.color}15`,
              display: "flex", alignItems: "center", justifyContent: "center",
              fontSize: 20, flexShrink: 0,
            }}>{s.icon}</div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.bleuFonce }}>{s.name}</div>
              <div style={{ fontSize: 11, color: COLORS.gris }}>{s.sub}</div>
            </div>
            <a href={`tel:${s.num}`} style={{
              background: COLORS.vert, color: "#fff", borderRadius: 10,
              padding: "8px 12px", textDecoration: "none", fontSize: 13, fontWeight: 700,
            }}>{s.num}</a>
          </div>
        ))}
      </div>
      <NavBar active="annuaire" setScreen={setScreen} />
    </div>
  );
};

const DashboardScreen = ({ setScreen }) => {
  const bars = [
    { label: "Lun", val: 2, color: COLORS.vert },
    { label: "Mar", val: 5, color: COLORS.orange },
    { label: "Mer", val: 3, color: COLORS.orange },
    { label: "Jeu", val: 8, color: COLORS.rouge },
    { label: "Ven", val: 6, color: COLORS.rouge },
    { label: "Sam", val: 4, color: COLORS.orange },
    { label: "Dim", val: 1, color: COLORS.vert },
  ];
  const maxVal = Math.max(...bars.map(b => b.val));
  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: 568, background: "#fff" }}>
      <StatusBar />
      <TopBar title="Tableau de bord — Votre quartier" />
      <div style={{ flex: 1, padding: "14px 14px 8px", overflow: "auto" }}>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginBottom: 16 }}>
          {[
            { label: "Incidents cette semaine", val: "29", icon: "⚠️", color: COLORS.rouge },
            { label: "Alertes SOS envoyées", val: "7", icon: "🆘", color: COLORS.orange },
            { label: "Utilisateurs actifs", val: "342", icon: "👥", color: COLORS.bleu },
            { label: "Zones sécurisées", val: "4", icon: "🟢", color: COLORS.vert },
          ].map(m => (
            <div key={m.label} style={{
              background: COLORS.grisClair, borderRadius: 10,
              padding: "10px 12px",
            }}>
              <div style={{ fontSize: 18 }}>{m.icon}</div>
              <div style={{ fontSize: 20, fontWeight: 800, color: m.color, marginTop: 4 }}>{m.val}</div>
              <div style={{ fontSize: 9, color: COLORS.gris, marginTop: 2, lineHeight: 1.3 }}>{m.label}</div>
            </div>
          ))}
        </div>
        <div style={{ background: COLORS.grisClair, borderRadius: 12, padding: "12px 14px", marginBottom: 14 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.bleuFonce, marginBottom: 12 }}>INCIDENTS PAR JOUR (7 derniers jours)</div>
          <div style={{ display: "flex", alignItems: "flex-end", gap: 6, height: 80 }}>
            {bars.map((b, i) => (
              <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 4 }}>
                <div style={{ fontSize: 9, color: b.color, fontWeight: 700 }}>{b.val}</div>
                <div style={{
                  width: "100%", background: b.color, borderRadius: "4px 4px 0 0",
                  height: `${(b.val / maxVal) * 60}px`,
                  transition: "height 0.3s",
                }} />
                <div style={{ fontSize: 8, color: COLORS.gris }}>{b.label}</div>
              </div>
            ))}
          </div>
        </div>
        <div style={{ background: COLORS.grisClair, borderRadius: 12, padding: "12px 14px" }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.bleuFonce, marginBottom: 10 }}>HEURES À RISQUE</div>
          {[
            { label: "18h – 20h", level: 90, color: COLORS.rouge },
            { label: "20h – 22h", level: 75, color: COLORS.rouge },
            { label: "12h – 14h", level: 45, color: COLORS.orange },
            { label: "06h – 08h", level: 20, color: COLORS.vert },
          ].map((h, i) => (
            <div key={i} style={{ marginBottom: 8 }}>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 3 }}>
                <span style={{ fontSize: 10, color: COLORS.gris }}>{h.label}</span>
                <span style={{ fontSize: 10, fontWeight: 600, color: h.color }}>{h.level}%</span>
              </div>
              <div style={{ background: "#ddd", borderRadius: 4, height: 6, overflow: "hidden" }}>
                <div style={{ width: `${h.level}%`, height: "100%", background: h.color, borderRadius: 4 }} />
              </div>
            </div>
          ))}
        </div>
      </div>
      <NavBar active="dashboard" setScreen={setScreen} />
    </div>
  );
};

export default function SafeAlertPrototype() {
  const [screen, setScreen] = useState("brand");

  const renderScreen = () => {
    switch (screen) {
      case "brand": return <BrandScreen />;
      case "splash": return <SplashScreen setScreen={setScreen} />;
      case "home": return <HomeScreen setScreen={setScreen} />;
      case "sos": return <SOSScreen setScreen={setScreen} />;
      case "map": return <MapScreen setScreen={setScreen} />;
      case "contacts": return <ContactsScreen setScreen={setScreen} />;
      case "annuaire": return <AnnuaireScreen setScreen={setScreen} />;
      case "dashboard": return <DashboardScreen setScreen={setScreen} />;
      default: return <HomeScreen setScreen={setScreen} />;
    }
  };

  return (
    <div style={{ padding: "20px 0", background: "var(--color-background-tertiary)", minHeight: "100vh" }}>
      <div style={{ textAlign: "center", marginBottom: 20 }}>
        <div style={{ fontSize: 11, fontWeight: 700, color: "var(--color-text-secondary)", letterSpacing: 2, marginBottom: 12 }}>
          SAFEALERT — PROTOTYPE INTERACTIF
        </div>
        <div style={{ display: "flex", justifyContent: "center", flexWrap: "wrap", gap: 6, maxWidth: 480, margin: "0 auto" }}>
          {screens.map(s => (
            <button key={s} onClick={() => setScreen(s)} style={{
              padding: "5px 12px",
              background: screen === s ? COLORS.rouge : "transparent",
              color: screen === s ? "#fff" : "var(--color-text-secondary)",
              border: `1px solid ${screen === s ? COLORS.rouge : "var(--color-border-tertiary)"}`,
              borderRadius: 20,
              fontSize: 11,
              fontWeight: screen === s ? 700 : 400,
              cursor: "pointer",
            }}>{screenLabels[s]}</button>
          ))}
        </div>
      </div>
      <Phone>{renderScreen()}</Phone>
      <div style={{ textAlign: "center", marginTop: 16, fontSize: 10, color: "var(--color-text-tertiary)" }}>
        Naviguez entre les écrans via les onglets ci-dessus ou les boutons dans l'app
      </div>
    </div>
  );
}
