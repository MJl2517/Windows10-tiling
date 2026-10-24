// Managed binaries move between version folders; tray preferences must not.
export function stableTrayKey(key: string): string {
  if (!key.startsWith("exe:")) return key;
  const path = key.replaceAll("\\", "/").toLowerCase();
  const managed = path.match(/\/packages\/(glazewm|zebar)\/[^/]+\/.*(?:glazewm|zebar)\.exe\|(\d+)$/)
    ?? path.match(/\/glzr\.io\/(glazewm|zebar)\/(?:cli\/)?(?:glazewm|zebar)\.exe\|(\d+)$/);
  return managed ? `exe:rpd:${managed[1]}|${managed[2]}` : key;
}
