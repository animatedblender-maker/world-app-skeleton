export const oceanColor = "#5B7FA6";

export const continentColors = {
  Africa:          "rgba(201,164,106,0.90)",
  Europe:          "rgba(143,174,143,0.90)",
  Asia:            "rgba(176,122,90,0.90)",
  "North America": "rgba(124,143,166,0.90)",
  "South America": "rgba(184,147,109,0.90)",
  Oceania:         "rgba(142,142,142,0.90)",
  Antarctica:      "rgba(220,220,220,0.85)",
  Unknown:         "rgba(160,160,160,0.85)"
};

export function getContinent(feature) {
  const p = feature?.properties || {};
  return p.CONTINENT || p.continent || "Unknown";
}
