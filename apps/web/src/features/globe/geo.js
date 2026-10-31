export function simpleCentroid(geometry) {
  let coords = [];
  if (geometry.type === "Polygon") coords = geometry.coordinates.flat();
  else if (geometry.type === "MultiPolygon") coords = geometry.coordinates.flat(2);

  let latSum = 0, lngSum = 0, count = 0;
  coords.forEach(([lng, lat]) => {
    if (Number.isFinite(lat) && Number.isFinite(lng)) { latSum += lat; lngSum += lng; count++; }
  });
  if (!count) return null;
  return { lat: latSum / count, lng: lngSum / count };
}

export function bboxOfGeometry(geometry) {
  let coords = [];
  if (geometry.type === "Polygon") coords = geometry.coordinates.flat();
  else if (geometry.type === "MultiPolygon") coords = geometry.coordinates.flat(2);

  let minLat =  999, maxLat = -999, minLng =  999, maxLng = -999;
  coords.forEach(([lng, lat]) => {
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
    minLat = Math.min(minLat, lat); maxLat = Math.max(maxLat, lat);
    minLng = Math.min(minLng, lng); maxLng = Math.max(maxLng, lng);
  });
  if (minLat > maxLat || minLng > maxLng) return null;
  return { dLat: (maxLat - minLat), dLng: (maxLng - minLng) };
}

export function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

export function computeLabelSizeFromBBox(bbox) {
  const span = Math.max(bbox.dLat, bbox.dLng);
  return clamp(0.55 + (span / 45) * 0.55, 0.55, 1.25);
}

export function computeAltitudeFromBBox(bbox) {
  const span = Math.max(bbox.dLat, bbox.dLng);
  const alt = 2.15 - (span / 60) * 1.25;
  return clamp(alt, 0.65, 2.25);
}

export function normalizeName(s) {
  return (s || "").trim().toLowerCase()
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ")
    .replace(/[’']/g, "'");
}

export async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

export async function flyTo(globe, lat, lng, targetAlt) {
  const pov = globe.pointOfView();
  const currentAlt = pov?.altitude ?? 2.0;

  if (currentAlt < 1.2) {
    globe.pointOfView({ lat: pov.lat, lng: pov.lng, altitude: 1.6 }, 550);
    await sleep(560);
  }
  globe.pointOfView({ lat, lng, altitude: 1.55 }, 850);
  await sleep(860);
  globe.pointOfView({ lat, lng, altitude: targetAlt }, 900);
}
