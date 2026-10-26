import { useEffect, useRef } from "react";
import type { SafeTripDetail } from "../api/client";

type LeafletNs = {
  map: (el: HTMLElement) => {
    setView: (ll: [number, number], z: number) => unknown;
    panTo: (ll: [number, number]) => void;
    fitBounds: (b: unknown, o?: { padding: [number, number] }) => void;
    remove: () => void;
  };
  tileLayer: (url: string, opts: { attribution: string }) => { addTo: (m: unknown) => void };
  marker: (ll: [number, number]) => {
    addTo: (m: unknown) => unknown;
    bindPopup: (html: string) => { openPopup: () => void; setPopupContent: (h: string) => { openPopup: () => void } };
    setLatLng: (ll: [number, number]) => void;
    setPopupContent: (html: string) => { openPopup: () => void };
    openPopup: () => void;
  };
  polyline: (
    pts: [number, number][],
    opts: { color: string; weight: number; opacity: number }
  ) => {
    addTo: (m: unknown) => unknown;
    setLatLngs: (pts: [number, number][]) => void;
    getBounds: () => unknown;
  };
};

declare global {
  interface Window {
    L?: LeafletNs;
  }
}

type Props = {
  trip: SafeTripDetail;
  height?: number;
};

function loadLeaflet(): Promise<LeafletNs> {
  return new Promise((resolve, reject) => {
    if (window.L) {
      resolve(window.L);
      return;
    }
    const existing = document.querySelector<HTMLScriptElement>('script[data-leaflet="1"]');
    if (existing) {
      existing.addEventListener("load", () => {
        if (window.L) resolve(window.L);
        else reject(new Error("Leaflet indisponible"));
      });
      return;
    }
    if (!document.querySelector('link[data-leaflet="1"]')) {
      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
      link.dataset.leaflet = "1";
      document.head.appendChild(link);
    }
    const script = document.createElement("script");
    script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
    script.dataset.leaflet = "1";
    script.onload = () => {
      if (window.L) resolve(window.L);
      else reject(new Error("Leaflet indisponible"));
    };
    script.onerror = () => reject(new Error("Impossible de charger Leaflet"));
    document.body.appendChild(script);
  });
}

function fmtWhen(iso?: string | null) {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString("fr-FR", {
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return iso;
  }
}

function trackLatLngs(trip: SafeTripDetail): [number, number][] {
  const pts: [number, number][] = [];
  for (const p of trip.track || []) {
    if (p?.lat != null && p?.lng != null) pts.push([p.lat, p.lng]);
  }
  if (!pts.length && trip.origin_lat != null && trip.origin_lng != null) {
    pts.push([trip.origin_lat, trip.origin_lng]);
  }
  const lat = trip.last_lat ?? trip.origin_lat;
  const lng = trip.last_lng ?? trip.origin_lng;
  if (lat != null && lng != null) {
    const last = pts[pts.length - 1];
    if (!last || last[0] !== lat || last[1] !== lng) pts.push([lat, lng]);
  }
  return pts;
}

type MapHandles = {
  map: ReturnType<LeafletNs["map"]>;
  marker: ReturnType<LeafletNs["marker"]>;
  trail: ReturnType<LeafletNs["polyline"]>;
  origin?: ReturnType<LeafletNs["marker"]>;
  dest?: ReturnType<LeafletNs["marker"]>;
};

/** Carte Leaflet lecture seule pour suivre / revoir un trajet admin. */
export default function TripTrackMap({ trip, height = 320 }: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<MapHandles | null>(null);

  useEffect(() => {
    let cancelled = false;
    if (!containerRef.current) return;

    void (async () => {
      try {
        const L = await loadLeaflet();
        if (cancelled || !containerRef.current) return;

        const lat = trip.last_lat ?? trip.origin_lat;
        const lng = trip.last_lng ?? trip.origin_lng;
        if (lat == null || lng == null) return;

        const trailPts = trackLatLngs(trip);

        if (!mapRef.current) {
          const map = L.map(containerRef.current);
          map.setView([lat, lng], 14);
          L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
            attribution: "&copy; OpenStreetMap",
          }).addTo(map);

          const origin =
            trip.origin_lat != null
              ? (L.marker([trip.origin_lat, trip.origin_lng]).addTo(map) as ReturnType<
                  LeafletNs["marker"]
                >)
              : undefined;
          origin
            ?.bindPopup(`<strong>Départ</strong><br/>${fmtWhen(trip.created_at)}`)
            .openPopup();

          const marker = L.marker([lat, lng]).addTo(map) as ReturnType<LeafletNs["marker"]>;
          marker.bindPopup("Position actuelle");

          const isPatrol = trip.trip_mode === "patrol";
          const dest =
            !isPatrol && trip.dest_lat != null
              ? (L.marker([trip.dest_lat, trip.dest_lng]).addTo(map) as ReturnType<
                  LeafletNs["marker"]
                >)
              : undefined;
          dest?.bindPopup(
            `<strong>${trip.arrived_at ? "Arrivée" : "Arrivée prévue"}</strong><br/>${fmtWhen(
              trip.arrived_at || trip.eta_at
            )}`
          );

          const line = L.polyline(trailPts.length ? trailPts : [[lat, lng]], {
            color: "#0B6E6E",
            weight: 4,
            opacity: 0.9,
          }).addTo(map) as ReturnType<LeafletNs["polyline"]>;

          if (trailPts.length > 1) {
            map.fitBounds(line.getBounds(), { padding: [28, 28] });
          }

          mapRef.current = { map, marker, trail: line, origin, dest };
        } else {
          const { map, marker, trail, origin, dest } = mapRef.current;
          marker.setLatLng([lat, lng]);
          trail.setLatLngs(trailPts.length ? trailPts : [[lat, lng]]);
          origin
            ?.setPopupContent(`<strong>Départ</strong><br/>${fmtWhen(trip.created_at)}`)
            .openPopup();
          dest?.setPopupContent(
            `<strong>${trip.arrived_at ? "Arrivée" : "Arrivée prévue"}</strong><br/>${fmtWhen(
              trip.arrived_at || trip.eta_at
            )}`
          );
          if (trip.status === "active") map.panTo([lat, lng]);
        }
      } catch {
        /* map optional */
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [trip]);

  useEffect(() => {
    return () => {
      mapRef.current?.map.remove();
      mapRef.current = null;
    };
  }, []);

  return (
    <div style={{ marginTop: 12 }}>
      <div
        style={{
          display: "flex",
          flexWrap: "wrap",
          gap: 12,
          marginBottom: 8,
          fontSize: 13,
        }}
      >
        <span>
          <strong>Départ</strong> {fmtWhen(trip.created_at)}
        </span>
        <span>
          <strong>{trip.arrived_at ? "Arrivée" : "Arrivée prévue"}</strong>{" "}
          {fmtWhen(trip.arrived_at || trip.eta_at)}
        </span>
      </div>
      <div
        ref={containerRef}
        style={{
          height,
          width: "100%",
          borderRadius: 10,
          overflow: "hidden",
          border: "1px solid rgba(0,0,0,0.08)",
          background: "#e8eef0",
        }}
      />
    </div>
  );
}
