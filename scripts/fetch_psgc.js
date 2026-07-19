import { writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const OUT_DIR = join(__dirname, '..', 'assets', 'data');

mkdirSync(OUT_DIR, { recursive: true });

const BASE = 'https://psgc.gitlab.io/api';

async function fetchJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return res.json();
}

async function main() {
  console.log('Fetching regions...');
  const regions = await fetchJSON(`${BASE}/regions.json`);

  const regionsClean = regions.map(r => ({
    code: r.code,
    name: r.name,
  }));

  writeFileSync(join(OUT_DIR, 'regions.json'), JSON.stringify(regionsClean, null, 2));
  console.log(`  ${regionsClean.length} regions saved`);

  const provincesByRegion = {};
  const citiesByProvince = {};

  for (const region of regions) {
    console.log(`Fetching provinces for ${region.name} (${region.code})...`);
    try {
      const provinces = await fetchJSON(`${BASE}/regions/${region.code}/provinces.json`);
      provincesByRegion[region.code] = provinces.map(p => ({
        code: p.code,
        name: p.name,
      }));

      if (provinces.length === 0) {
        throw new Error('No provinces found');
      }

      for (const province of provinces) {
        console.log(`  Fetching cities for ${province.name} (${province.code})...`);
        try {
          const cities = await fetchJSON(`${BASE}/provinces/${province.code}/cities-municipalities.json`);
          citiesByProvince[province.code] = cities.map(c => ({
            code: c.code,
            name: c.name,
            isCapital: c.isCapital ?? false,
          }));
        } catch (e) {
          console.log(`    Warning: ${e.message}`);
          citiesByProvince[province.code] = [];
        }
      }
    } catch (e) {
      console.log(`  Warning: ${e.message} — region may have no provinces (e.g. NCR). Fetching cities/municipalities directly...`);
      provincesByRegion[region.code] = [];
      try {
        const cities = await fetchJSON(`${BASE}/regions/${region.code}/cities-municipalities.json`);
        citiesByProvince[region.code] = cities.map(c => ({
          code: c.code,
          name: c.name,
          isCapital: c.isCapital ?? false,
        }));
        console.log(`    Saved ${citiesByProvince[region.code].length} cities/municipalities for ${region.name}`);
      } catch (e2) {
        console.log(`    Warning: ${e2.message} — no cities found directly under region either`);
        citiesByProvince[region.code] = [];
      }
    }
  }

  writeFileSync(join(OUT_DIR, 'provinces_by_region.json'), JSON.stringify(provincesByRegion, null, 2));
  writeFileSync(join(OUT_DIR, 'cities_municipalities.json'), JSON.stringify(citiesByProvince, null, 2));

  const totalProvinces = Object.values(provincesByRegion).reduce((s, arr) => s + arr.length, 0);
  const totalCities = Object.values(citiesByProvince).reduce((s, arr) => s + arr.length, 0);
  console.log(`Done: ${totalProvinces} provinces, ${totalCities} cities/municipalities`);
}

main().catch(e => { console.error(e); process.exit(1); });
