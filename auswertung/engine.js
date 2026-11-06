/*
 * myUplink-Logger – Auswertung im Browser
 * Portierung von Invoke-MyUplinkAuswertung (MyUplink-Auswertung.ps1, Version 2.4.0).
 * Läuft im Browser und in Node.js. Liest nur die CSV, nichts wird übertragen.
 * Lizenz: MIT
 */
(function (root) {
  'use strict';

  // Parameter-IDs der Paros 4-2 (siehe docs/parameter.md)
  const ID = {
    Vorlauf: '0', Ruecklauf: '1', Aussen: '5', Zustand: '17', Leistung: '21',
    MischerIst: '23', MischerSoll: '22', RuecklaufExt: '3', RuecklaufSoll: '2',
    HUP: '32', ZUP: '33',
    // Luxtronik direkt (Modbus TCP), ID = MB + Registeradresse
    LuxPth: 'MB10300', LuxVL: 'MB10105', LuxPel: 'MB10301',
    LuxStromGes: 'MB10310', LuxStromHz: 'MB10312', LuxStromWW: 'MB10314',
    LuxWaermeGes: 'MB10320', LuxWaermeHz: 'MB10322', LuxWaermeWW: 'MB10324',
    Durchfluss: '31', Verdichter: '70', Impulse: '5674', Offset: '5001', Heizgrenze: '5700'
  };
  const Z_HEIZ = 0, Z_WW = 1, Z_ABTAU = 4;
  const MIN = 60000;
  const NaN_ = Number.NaN;

  // ---------- Hilfsfunktionen ----------

  // Runden wie .NET [math]::Round (kaufmännisch zur geraden Zahl bei exakt .5)
  function rnd(x, d) {
    const f = Math.pow(10, d || 0);
    const y = x * f;
    const fl = Math.floor(y);
    const diff = y - fl;
    let r;
    if (diff === 0.5) r = (fl % 2 === 0) ? fl : fl + 1;
    else r = Math.round(y);
    return r / f + 0;
  }

  function zahl(s) {
    if (s === undefined || s === null) return NaN_;
    let t = String(s).trim();
    if (t === '') return NaN_;
    if (t.indexOf(',') >= 0 && t.indexOf('.') < 0) t = t.replace(',', '.');
    if (!/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(t)) return NaN_;
    return Number(t);
  }

  function mittel() { return { S: 0, N: 0 }; }
  function addM(m, x) { if (!Number.isNaN(x)) { m.S += x; m.N++; } }
  function getM(m, d) { return m.N > 0 ? rnd(m.S / m.N, d === undefined ? 1 : d) : null; }
  function median(werte, d) {
    const a = werte.filter(v => v !== null && v !== undefined).map(Number).sort((x, y) => x - y);
    if (!a.length) return null;
    const m = a.length % 2 ? a[Math.floor(a.length / 2)] : (a[a.length / 2 - 1] + a[a.length / 2]) / 2;
    return rnd(m, d === undefined ? 1 : d);
  }
  function tagBeginn(ms) { const t = new Date(ms); return new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime(); }
  function tagSchluessel(ms) {
    const t = new Date(ms);
    return t.getFullYear() + '-' + String(t.getMonth() + 1).padStart(2, '0') + '-' + String(t.getDate()).padStart(2, '0');
  }

  // Zeitangaben: "Abgerufen" ist lokale Zeit ohne Zone, "Zeitstempel" ISO mit Zone
  function parseLokal(s) {
    if (!s) return NaN_;
    let m = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?/.exec(s);
    if (m) return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0)).getTime();
    m = /^(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2})(?::(\d{2}))?/.exec(s);
    if (m) return new Date(+m[3], +m[2] - 1, +m[1], +m[4], +m[5], +(m[6] || 0)).getTime();
    return NaN_;
  }
  function parseZeitstempel(s) {
    if (!s) return NaN_;
    const t = Date.parse(s);
    return Number.isNaN(t) ? parseLokal(s) : t;
  }

  // ---------- CSV ----------

  // Semikolon-CSV wie von Export-Csv (Felder in Anführungszeichen, UTF-8 mit BOM)
  function parseCsv(text) {
    if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
    const rows = [];
    let feld = '', zeile = [], inQ = false;
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (inQ) {
        if (c === '"') {
          if (text[i + 1] === '"') { feld += '"'; i++; } else inQ = false;
        } else feld += c;
      } else if (c === '"') inQ = true;
      else if (c === ';') { zeile.push(feld); feld = ''; }
      else if (c === '\n' || c === '\r') {
        if (c === '\r' && text[i + 1] === '\n') i++;
        zeile.push(feld); feld = '';
        if (zeile.length > 1 || zeile[0] !== '') rows.push(zeile);
        zeile = [];
      } else feld += c;
    }
    if (feld !== '' || zeile.length) { zeile.push(feld); rows.push(zeile); }
    if (!rows.length) return [];
    const kopf = rows[0].map(h => h.trim());
    const idx = n => kopf.indexOf(n);
    const need = ['Abgerufen', 'Geraet', 'ParameterId', 'Wert', 'Zeitstempel'];
    for (const n of need) if (idx(n) < 0) throw new Error('Spalte "' + n + '" fehlt – ist das eine Logdatei des myUplink-Loggers?');
    const iA = idx('Abgerufen'), iG = idx('Geraet'), iP = idx('ParameterId'), iW = idx('Wert'), iZ = idx('Zeitstempel'), iN = idx('Name');
    const out = new Array(rows.length - 1);
    for (let r = 1; r < rows.length; r++) {
      const z = rows[r];
      out[r - 1] = { Abgerufen: z[iA], Geraet: z[iG], ParameterId: z[iP], Wert: z[iW], Zeitstempel: z[iZ], Name: iN >= 0 ? z[iN] : '' };
    }
    return out;
  }

  // Treppenfunktion einer Messreihe auf ein Minutenraster legen
  function raster(reihe, start, n) {
    const out = new Float64Array(n);
    if (!reihe) { out.fill(NaN_); return out; }
    const T = reihe.T, V = reihe.V;
    let i = 0, cur = NaN_;
    for (let k = 0; k < n; k++) {
      const jetzt = start + k * MIN;
      while (i < T.length && T[i] <= jetzt) { cur = V[i]; i++; }
      out[k] = cur;
    }
    return out;
  }

  // ---------- Auswertung ----------

  function analysiere(zeilen, opt) {
    opt = opt || {};
    const einschwing = opt.einschwingMinuten !== undefined ? opt.einschwingMinuten : 10;
    const lueckeMin = opt.lueckeMinuten !== undefined ? opt.lueckeMinuten : 30;
    if (!zeilen.length) throw new Error('Die Logdatei enthält keine Daten.');

    // 1. Geräte und Messreihen
    const geraete = [];
    for (const z of zeilen) if (!String(z.ParameterId).startsWith('MB') && geraete.indexOf(z.Geraet) < 0) geraete.push(z.Geraet);
    if (!geraete.length) geraete.push(zeilen[0].Geraet);
    const deviceId = opt.deviceId || geraete[0];
    const warnungen = [];
    if (geraete.length > 1 && !opt.deviceId) warnungen.push('Mehrere Geräte in der Datei, ausgewertet wird ' + deviceId + '.');

    const roh = new Map();
    const abrufe = new Set();
    for (const z of zeilen) {
      const pid = String(z.ParameterId);
      if (z.Geraet !== deviceId && !pid.startsWith('MB')) continue;
      const a = parseLokal(z.Abgerufen), t = parseZeitstempel(z.Zeitstempel);
      if (Number.isNaN(a) || Number.isNaN(t)) continue;
      abrufe.add(a - (((a % MIN) + MIN) % MIN));
      let m = roh.get(pid);
      if (!m) { m = new Map(); roh.set(pid, m); }
      m.set(t, zahl(z.Wert));     // gleicher Zeitstempel = gleicher Messwert
    }
    const reihe = {};
    for (const [pid, m] of roh) {
      const keys = Array.from(m.keys()).sort((x, y) => x - y);
      reihe[pid] = { T: keys, V: keys.map(k => m.get(k)) };
    }
    for (const p of [ID.Verdichter, ID.Impulse, ID.Zustand]) {
      if (!reihe[p]) throw new Error('Parameter-ID ' + p + ' fehlt im Log. Bitte mit der Standardauswahl loggen.');
    }

    // 2. Minutenraster
    const abrufListe = Array.from(abrufe).sort((x, y) => x - y);
    let start = abrufListe[0], ende = abrufListe[abrufListe.length - 1];
    if (opt.von) start = Math.max(start, tagBeginn(opt.von));
    if (opt.bis) { const b = new Date(opt.bis); ende = Math.min(ende, new Date(b.getFullYear(), b.getMonth(), b.getDate() + 1).getTime() - MIN); }
    if (ende <= start) throw new Error('Im gewählten Zeitraum liegen keine Daten.');
    const n = Math.round((ende - start) / MIN) + 1;

    const abgedeckt = new Uint8Array(n);
    let j = 0;
    for (let k = 0; k < n; k++) {
      const t = start + k * MIN;
      while (j + 1 < abrufListe.length && abrufListe[j + 1] <= t) j++;
      if (lueckeMin <= 0) { abgedeckt[k] = 1; continue; }
      const vor = abrufListe[j];
      const nach = j + 1 < abrufListe.length ? abrufListe[j + 1] : vor;
      abgedeckt[k] = (t >= vor && (nach - vor) <= lueckeMin * MIN) ? 1 : 0;
    }

    const r = {};
    for (const name in ID) r[name] = raster(reihe[ID[name]], start, n);

    // 3. Verdichterläufe aus den Schaltzeitpunkten von VD1
    const vd = reihe[ID.Verdichter];
    const laeufe = [];
    let an = null;
    for (let i = 0; i < vd.T.length; i++) {
      const ein = vd.V[i] >= 0.5;
      if (ein) {
        if (an !== null) laeufe.push({ A: an, E: null, Status: 'Aus-Signal fehlt' });
        an = vd.T[i];
      } else if (an !== null) {
        laeufe.push({ A: an, E: vd.T[i], Status: 'vollständig' });
        an = null;
      }
    }
    if (an !== null) laeufe.push({ A: an, E: null, Status: 'läuft noch' });

    const alter = new Int32Array(n).fill(-1);
    const zyklen = [];
    let vorEnde = null;
    const wert = (arr, k) => (k >= 0 && k < n && abgedeckt[k] && !Number.isNaN(arr[k])) ? rnd(arr[k], 1) : null;

    for (const l of laeufe) {
      const endeL = l.E === null ? ende : l.E;
      if (endeL < start || l.A > ende) { vorEnde = l.E; continue; }
      const i0 = Math.ceil((l.A - start) / MIN);
      const i1 = Math.floor((endeL - start) / MIN);
      let status = l.Status;
      if (l.A < start || (l.E !== null && l.E > ende)) status = 'außerhalb Zeitraum';

      const mVL = mittel(), mRL = mittel(), mAT = mittel(), mMK = mittel(), mP = mittel(), mQ = mittel();
      const mMS = mittel(), mMA = mittel(), mRX = mittel(), mPel = mittel(), mWP = mittel(), mFD = mittel();
      let sumPth = 0, sumPel = 0, ww = 0, luecke = false;
      for (let k = Math.max(i0, 0); k < Math.min(i1, n); k++) {
        alter[k] = k - i0;
        if (!abgedeckt[k]) { luecke = true; continue; }
        const zu = r.Zustand[k];
        if (zu === Z_WW) ww++;
        if (zu === Z_HEIZ && (k - i0) >= einschwing) {
          addM(mVL, r.Vorlauf[k]); addM(mRL, r.Ruecklauf[k]);
          addM(mMK, r.MischerIst[k]); addM(mP, r.Leistung[k]); addM(mQ, r.Durchfluss[k]);
          addM(mMS, r.MischerSoll[k]); addM(mRX, r.RuecklaufExt[k]);
          addM(mMA, r.MischerIst[k] - r.MischerSoll[k]);
          addM(mPel, r.LuxPel[k]);
          if (!Number.isNaN(r.LuxPth[k]) && !Number.isNaN(r.LuxPel[k])) { sumPth += r.LuxPth[k]; sumPel += r.LuxPel[k]; }
          addM(mWP, r.Vorlauf[k] - r.RuecklaufExt[k]);
          addM(mFD, r.Durchfluss[k] * 1.163 * (r.Vorlauf[k] - r.Ruecklauf[k]) / 1000);
        }
        addM(mAT, r.Aussen[k]);
      }
      if (luecke && status === 'vollständig') status = 'Lücke im Log';

      let abtau = 0;
      const zs = reihe[ID.Zustand];
      for (let i = 0; i < zs.T.length; i++) {
        if (zs.T[i] >= l.A && zs.T[i] <= endeL && zs.V[i] === Z_ABTAU && (i === 0 || zs.V[i - 1] !== Z_ABTAU)) abtau++;
      }

      const dauer = l.E !== null ? rnd((l.E - l.A) / MIN, 0) : null;
      let pause = null;
      if (vorEnde !== null && l.A >= start) {
        const p0 = Math.max(0, Math.floor((vorEnde - start) / MIN));
        const p1 = Math.min(n - 1, i0);
        let ok = true;
        for (let k = p0; k <= p1; k++) if (!abgedeckt[k]) { ok = false; break; }
        if (ok) pause = rnd((l.A - vorEnde) / MIN, 0);
      }

      const pufS = wert(r.RuecklaufExt, i0 - 1), solS = wert(r.RuecklaufSoll, i0 - 1);
      let pufE = null, solE = null, vlE = null;
      if (status === 'vollständig' && i1 - 1 >= i0) {
        pufE = wert(r.RuecklaufExt, i1 - 1); solE = wert(r.RuecklaufSoll, i1 - 1); vlE = wert(r.Vorlauf, i1 - 1);
      }
      const vlm = getM(mVL), rlm = getM(mRL);
      zyklen.push({
        Start: l.A, Ende: l.E,
        Dauer_min: dauer, Pause_vorher_min: pause,
        Aussen_C: getM(mAT), Vorlauf_C: vlm, Ruecklauf_C: rlm,
        Spreizung_K: (vlm !== null && rlm !== null) ? rnd(vlm - rlm, 1) : null,
        Mischer_Vorlauf_C: getM(mMK), Mischer_Soll_C: getM(mMS), Mischer_Abw_K: getM(mMA),
        Ruecklauf_ext_C: getM(mRX), Abstand_WP_Puffer_K: getM(mWP),
        Puffer_Start_C: pufS, RL_Soll_Start_C: solS,
        Schalt_Start_K: (pufS !== null && solS !== null) ? rnd(pufS - solS, 1) : null,
        Puffer_Stopp_C: pufE,
        Schalt_Stopp_K: (pufE !== null && solE !== null) ? rnd(pufE - solE, 1) : null,
        Vorlauf_Stopp_C: vlE,
        Leistung_kW: getM(mP, 2), Leistung_el_kW: getM(mPel, 2),
        COP: sumPel > 0 ? rnd(sumPth / sumPel, 2) : null,
        Durchfluss_lh: getM(mQ, 0), Leistung_aus_Durchfluss_kW: getM(mFD, 2),
        Abtauungen: abtau, WW_min: ww, Status: status
      });
      vorEnde = l.E;
    }

    // 4. Abtau- und Warmwasserphasen
    const phasen = [];
    {
      const zs = reihe[ID.Zustand];
      for (let i = 0; i < zs.T.length; i++) {
        const v = zs.V[i];
        if ((v === Z_ABTAU || v === Z_WW) && (i === 0 || zs.V[i - 1] !== v) && zs.T[i] >= start && zs.T[i] <= ende) {
          phasen.push({ Art: v === Z_WW ? 'WW' : 'Abtau', Tag: tagSchluessel(zs.T[i]) });
        }
      }
    }

    // 5. Tageswerte
    const neuerTag = () => ({
      Cov: 0, AT: mittel(), An: 0, VL: mittel(), RL: mittel(), MK: mittel(), Abst: mittel(), kWh: 0, Abtau: 0, WW: 0,
      First: -1, Last: -1, Offset: null, HG: null, MS: mittel(), MA: mittel(), RX: mittel(),
      HUP: 0, HUPn: 0, HUPaus: 0, ZUP: 0, ZUPn: 0, ZUPaus: 0,
      WPPuf: mittel(), PufMK: mittel(), Pref: mittel(), Fl: mittel(), Spr: mittel(), MKTn: 0, MKTx: 0, MKNn: 0, MKNx: 0
    });
    const klassen = [[46, 'bis 46 °C'], [48, '46-48 °C'], [50, '48-50 °C'], [52, '50-52 °C'], [54, '52-54 °C'], [999, 'über 54 °C']]
      .map(([bis, name]) => ({ Bis: bis, Name: name, Min: 0, Pth: 0, Pel: 0, AT: mittel() }));
    const tage = new Map();
    const gesamt = neuerTag();
    const proOffset = new Map();
    for (let k = 0; k < n; k++) {
      const tms = start + k * MIN;
      const tag = tagSchluessel(tms);
      if (!tage.has(tag)) tage.set(tag, neuerTag());
      if (abgedeckt[k] && r.Verdichter[k] >= 0.5 && r.Zustand[k] === Z_HEIZ && alter[k] >= einschwing && !Number.isNaN(r.Offset[k])) {
        const o = r.Offset[k];
        if (!proOffset.has(o)) proOffset.set(o, { Ab: tms, Min: 0, AT: mittel(), VL: mittel(), RL: mittel(), MK: mittel(), MS: mittel(), Abst: mittel(), Pth: 0, Pel: 0 });
        const g = proOffset.get(o);
        g.Min++;
        addM(g.AT, r.Aussen[k]); addM(g.VL, r.Vorlauf[k]); addM(g.RL, r.Ruecklauf[k]);
        addM(g.MK, r.MischerIst[k]); addM(g.MS, r.MischerSoll[k]); addM(g.Abst, r.Vorlauf[k] - r.MischerIst[k]);
        if (!Number.isNaN(r.LuxPth[k]) && !Number.isNaN(r.LuxPel[k])) { g.Pth += r.LuxPth[k]; g.Pel += r.LuxPel[k]; }
      }
      const heizMin = abgedeckt[k] && r.Verdichter[k] >= 0.5 && r.Zustand[k] === Z_HEIZ && alter[k] >= einschwing;
      const vlK = !Number.isNaN(r.LuxVL[k]) ? r.LuxVL[k] : r.Vorlauf[k];
      if (heizMin && !Number.isNaN(r.LuxPth[k]) && !Number.isNaN(r.LuxPel[k]) && !Number.isNaN(vlK)) {
        for (const kl of klassen) if (vlK < kl.Bis) { kl.Min++; kl.Pth += r.LuxPth[k]; kl.Pel += r.LuxPel[k]; addM(kl.AT, r.Aussen[k]); break; }
      }
      const stunde = new Date(tms).getHours();
      for (const acc of [tage.get(tag), gesamt]) {
        if (acc.First < 0) acc.First = k;
        acc.Last = k;
        if (!abgedeckt[k]) continue;
        acc.Cov++;
        addM(acc.AT, r.Aussen[k]);
        const ein = r.Verdichter[k] >= 0.5;
        if (ein) acc.An++;
        const zu = r.Zustand[k];
        if (ein && zu === Z_ABTAU) acc.Abtau++;
        if (ein && zu === Z_WW) acc.WW++;
        if (ein && zu === Z_HEIZ && alter[k] >= einschwing) {
          addM(acc.VL, r.Vorlauf[k]); addM(acc.RL, r.Ruecklauf[k]); addM(acc.MK, r.MischerIst[k]);
          if (!Number.isNaN(r.MischerIst[k]) && !Number.isNaN(r.Vorlauf[k])) addM(acc.Abst, r.Vorlauf[k] - r.MischerIst[k]);
          addM(acc.MS, r.MischerSoll[k]); addM(acc.RX, r.RuecklaufExt[k]);
          addM(acc.MA, r.MischerIst[k] - r.MischerSoll[k]);
          addM(acc.WPPuf, r.Vorlauf[k] - r.RuecklaufExt[k]);
          const pr = !Number.isNaN(r.LuxPth[k]) ? r.LuxPth[k] : r.Leistung[k];
          const sp = r.Vorlauf[k] - r.Ruecklauf[k];
          if (!Number.isNaN(pr) && pr > 0 && sp > 3 && r.Durchfluss[k] > 0) { addM(acc.Pref, pr); addM(acc.Spr, sp); addM(acc.Fl, r.Durchfluss[k]); }
        }
        addM(acc.PufMK, r.RuecklaufExt[k] - r.MischerSoll[k]);
        const dev = r.MischerIst[k] - r.MischerSoll[k];
        if (!Number.isNaN(dev)) {
          if (stunde >= 6 && stunde < 22) { acc.MKTn++; if (Math.abs(dev) > 2) acc.MKTx++; }
          else { acc.MKNn++; if (Math.abs(dev) > 2) acc.MKNx++; }
        }
        if (!Number.isNaN(r.HUP[k])) { acc.HUPn++; if (r.HUP[k] >= 0.5) { acc.HUP++; if (!ein) acc.HUPaus++; } }
        if (!Number.isNaN(r.ZUP[k])) { acc.ZUPn++; if (r.ZUP[k] >= 0.5) { acc.ZUP++; if (!ein) acc.ZUPaus++; } }
        const p = r.Leistung[k];
        if (ein && !Number.isNaN(p)) acc.kWh += p / 60;
        if (!Number.isNaN(r.Offset[k])) acc.Offset = r.Offset[k];
        if (!Number.isNaN(r.Heizgrenze[k])) acc.HG = r.Heizgrenze[k];
      }
    }

    const imp = r.Impulse;
    const delta = (arr, acc, streng) => {
      let e = NaN_, a = NaN_, iA = -1;
      for (let k = acc.Last; k >= acc.First; k--) if (!Number.isNaN(arr[k])) { e = arr[k]; break; }
      if (acc.First > 0 && !Number.isNaN(arr[acc.First - 1])) { a = arr[acc.First - 1]; iA = acc.First; }
      else for (let k = acc.First; k <= acc.Last; k++) if (!Number.isNaN(arr[k])) { a = arr[k]; iA = k; break; }
      if (Number.isNaN(e) || Number.isNaN(a)) return null;
      if (streng && (iA - acc.First) > 60) return null;
      if ((acc.Last - iA) < 60) return null;
      return rnd(e - a, 1);
    };
    let zaehlerAb = null;
    const zr = reihe[ID.LuxStromGes];
    if (zr && zr.T.length && zr.T[0] > start + 60 * MIN) zaehlerAb = zr.T[0];
    const quote = (q, e) => (q !== null && e !== null && e > 0) ? rnd(q / e, 2) : null;

    const baueZeile = (bez, acc, zyk, abtauN, wwN) => {
      const iA = acc.First > 0 ? acc.First - 1 : acc.First;
      let starts = null;
      if (!Number.isNaN(imp[acc.Last]) && !Number.isNaN(imp[iA])) starts = Math.round(imp[acc.Last] - imp[iA]);
      const voll = zyk.filter(z => z.Status === 'vollständig' && z.Dauer_min !== null);
      const dauern = voll.map(z => z.Dauer_min);
      const pausen = zyk.filter(z => z.Pause_vorher_min !== null).map(z => z.Pause_vorher_min);
      const avg = a => a.reduce((s, x) => s + x, 0) / a.length;
      const lzh = rnd(acc.An / 60, 1);
      const vl = getM(acc.VL), rl = getM(acc.RL);
      const streng = bez !== 'Gesamt';
      const eHz = delta(r.LuxStromHz, acc, streng), qHz = delta(r.LuxWaermeHz, acc, streng);
      const eWW = delta(r.LuxStromWW, acc, streng), qWW = delta(r.LuxWaermeWW, acc, streng);
      const eGs = delta(r.LuxStromGes, acc, streng), qGs = delta(r.LuxWaermeGes, acc, streng);
      const hinweis = [];
      if (acc.Cov < (acc.Last - acc.First + 1)) hinweis.push('Lücken im Log');
      if (!streng && zaehlerAb !== null && eGs !== null) {
        const d = new Date(zaehlerAb);
        hinweis.push('Zähler ab ' + String(d.getDate()).padStart(2, '0') + '.' + String(d.getMonth() + 1).padStart(2, '0') + '. ' +
          String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'));
      }
      if (bez !== 'Gesamt' && acc.Cov < 1380) hinweis.push('Tag unvollständig');
      return {
        Datum: bez,
        Abdeckung_h: rnd(acc.Cov / 60, 1),
        Aussen_C: getM(acc.AT),
        Starts: starts, Starts_erkannt: zyk.length,
        Laufzeit_h: lzh,
        Lauf_Mittel_min: dauern.length ? rnd(avg(dauern), 0) : null,
        Lauf_Min_min: dauern.length ? Math.min(...dauern) : null,
        Lauf_Max_min: dauern.length ? Math.max(...dauern) : null,
        Pause_Mittel_min: pausen.length ? rnd(avg(pausen), 0) : null,
        Starts_je_Laufstunde: (starts !== null && lzh > 0) ? rnd(starts / lzh, 2) : null,
        Vorlauf_C: vl, Ruecklauf_C: rl,
        Spreizung_K: (vl !== null && rl !== null) ? rnd(vl - rl, 1) : null,
        Mischer_Vorlauf_C: getM(acc.MK),
        Abstand_WP_Mischer_K: getM(acc.Abst),
        Abstand_WP_Puffer_K: getM(acc.WPPuf),
        Abstand_Puffer_Mischer_K: getM(acc.PufMK),
        Mischer_Soll_C: getM(acc.MS), Mischer_Abw_K: getM(acc.MA), Ruecklauf_ext_C: getM(acc.RX),
        Mischer_ueber2K_Tag_Proz: acc.MKTn > 0 ? rnd(100 * acc.MKTx / acc.MKTn, 0) : null,
        Mischer_ueber2K_Nacht_Proz: acc.MKNn > 0 ? rnd(100 * acc.MKNx / acc.MKNn, 0) : null,
        Schalt_Start_K: median(zyk.map(z => z.Schalt_Start_K)),
        Schalt_Stopp_K: median(zyk.map(z => z.Schalt_Stopp_K)),
        Durchfluss_angezeigt_lh: getM(acc.Fl, 0),
        Durchfluss_rechnerisch_lh: (acc.Spr.N > 0 && acc.Spr.S > 0) ? rnd(1000 * acc.Pref.S / acc.Pref.N / (1.163 * acc.Spr.S / acc.Spr.N), 0) : null,
        Abtauungen: abtauN, Abtau_min: acc.Abtau, WW_Ladungen: wwN, WW_min: acc.WW,
        HUP_h: acc.HUPn > 0 ? rnd(acc.HUP / 60, 1) : null,
        ZUP_h: acc.ZUPn > 0 ? rnd(acc.ZUP / 60, 1) : null,
        ZUP_ohne_Verdichter_h: acc.ZUPn > 0 ? rnd(acc.ZUPaus / 60, 1) : null,
        HUP_ohne_Verdichter_h: acc.HUPn > 0 ? rnd(acc.HUPaus / 60, 1) : null,
        Waerme_kWh: rnd(acc.kWh, 1),
        Strom_Heizen_kWh: eHz, Waerme_Heizen_kWh: qHz, AZ_Heizen: quote(qHz, eHz),
        Strom_WW_kWh: eWW, Waerme_WW_kWh: qWW, AZ_WW: quote(qWW, eWW),
        Strom_gesamt_kWh: eGs, Waerme_gesamt_kWh: qGs, AZ_gesamt: quote(qGs, eGs),
        Offset_K: acc.Offset, Heizgrenze_C: acc.HG,
        Hinweis: hinweis.join(', ')
      };
    };

    const tagZeilen = [];
    for (const [tag, acc] of tage) {
      const zyk = zyklen.filter(z => tagSchluessel(z.Start) === tag);
      const ab = phasen.filter(p => p.Art === 'Abtau' && p.Tag === tag).length;
      const wwn = phasen.filter(p => p.Art === 'WW' && p.Tag === tag).length;
      tagZeilen.push(baueZeile(tag, acc, zyk, ab, wwn));
    }
    const gesamtZeile = baueZeile('Gesamt', gesamt, zyklen.filter(z => z.Status !== 'außerhalb Zeitraum'),
      phasen.filter(p => p.Art === 'Abtau').length, phasen.filter(p => p.Art === 'WW').length);

    // Einstellungsänderungen
    const aenderungen = [];
    for (const e of [{ Id: ID.Offset, Name: 'Temperatur + -' }, { Id: ID.Heizgrenze, Name: 'Heizgrenze' }]) {
      const s = reihe[e.Id];
      if (!s) continue;
      for (let i = 0; i < s.T.length; i++) {
        if (i > 0 && s.V[i] === s.V[i - 1]) continue;
        aenderungen.push({ Zeit: s.T[i], Einstellung: e.Name, Wert: s.V[i] });
      }
    }

    // Je Einstellung "Temperatur + -"
    const offsetZeilen = [];
    for (const [o, x] of proOffset) {
      offsetZeilen.push({
        Offset_K: o, Erste_Heizminute: x.Ab, Heizstunden: rnd(x.Min / 60, 1),
        Aussen_C: getM(x.AT), Vorlauf_C: getM(x.VL), Ruecklauf_C: getM(x.RL),
        Mischer_Soll_C: getM(x.MS), Mischer_Vorlauf_C: getM(x.MK), Abstand_WP_Mischer_K: getM(x.Abst),
        COP: x.Pel > 0 ? rnd(x.Pth / x.Pel, 2) : null
      });
    }

    // Schaltpunkte und COP nach Vorlauf
    const sStart = zyklen.map(z => z.Schalt_Start_K).filter(v => v !== null);
    const sStopp = zyklen.map(z => z.Schalt_Stopp_K).filter(v => v !== null);
    const schaltpunkte = (sStart.length >= 3 && sStopp.length >= 3) ? {
      Laeufe: Math.min(sStart.length, sStopp.length),
      Start_Median_K: median(sStart), Start_Min_K: Math.min(...sStart), Start_Max_K: Math.max(...sStart),
      Stopp_Median_K: median(sStopp), Stopp_Min_K: Math.min(...sStopp), Stopp_Max_K: Math.max(...sStopp)
    } : null;
    const copNachVorlauf = klassen.filter(k => k.Min >= 15 && k.Pel > 0)
      .map(k => ({ Vorlauf: k.Name, Minuten: k.Min, COP: rnd(k.Pth / k.Pel, 2), Aussen_C: getM(k.AT) }));

    // Einschätzung (Faustregeln) – gleiche Regeln wie im PowerShell-Script
    const ein = [];
    const g = gesamtZeile;
    const fmt = v => String(v).replace('.', ',');
    if (g.Starts_je_Laufstunde !== null) {
      if (g.Starts_je_Laufstunde > 3) ein.push(['!', fmt(g.Starts_je_Laufstunde) + ' Starts je Laufstunde: deutliches Takten (Ziel: höchstens ca. 3).']);
      else ein.push(['+', fmt(g.Starts_je_Laufstunde) + ' Starts je Laufstunde: unkritisch.']);
    }
    if (g.Lauf_Mittel_min !== null) {
      if (g.Lauf_Mittel_min < 20) ein.push(['!', 'Ø Laufzeit ' + g.Lauf_Mittel_min + ' min: kurze Läufe (Ziel: mindestens 20 bis 30 min).']);
      else ein.push(['+', 'Ø Laufzeit ' + g.Lauf_Mittel_min + ' min: gut.']);
    }
    if (g.Spreizung_K !== null && g.Spreizung_K > 10) ein.push(['!', 'Spreizung WP-Vorlauf/Rücklauf ' + fmt(g.Spreizung_K) + ' K: groß (typisch 5 bis 8 K), Volumenstrom im Ladekreis prüfen lassen.']);
    if (g.Abstand_WP_Puffer_K !== null) {
      if (g.Abstand_WP_Puffer_K > 5) ein.push(['!', 'WP-Vorlauf liegt im Lauf ' + fmt(g.Abstand_WP_Puffer_K) + ' K über dem Puffer: Der Abstand entsteht im Ladekreis (Spreizung, Volumenstrom).']);
      if (g.Abstand_Puffer_Mischer_K !== null) {
        if (g.Abstand_Puffer_Mischer_K > 5) ein.push(['!', 'Puffer liegt im Mittel ' + fmt(g.Abstand_Puffer_Mischer_K) + ' K über dem Mischer-Soll: Rücklauf-Soll bzw. Heizkurve der WP prüfen.']);
        else ein.push(['+', 'Puffer liegt im Mittel ' + fmt(g.Abstand_Puffer_Mischer_K) + ' K über dem Mischer-Soll: Kurven gut aufeinander abgestimmt.']);
      }
    } else if (g.Abstand_WP_Mischer_K !== null && g.Abstand_WP_Mischer_K > 5) {
      ein.push(['!', 'WP-Vorlauf liegt ' + fmt(g.Abstand_WP_Mischer_K) + ' K über dem Mischerkreis-Vorlauf (Ursache: Spreizung, Puffer oder Heizkurve; ohne Pufferfühler nicht trennbar).']);
    }
    if (g.Durchfluss_rechnerisch_lh !== null && g.Durchfluss_angezeigt_lh !== null && g.Durchfluss_rechnerisch_lh > 0) {
      const v = g.Durchfluss_angezeigt_lh / g.Durchfluss_rechnerisch_lh;
      if (v > 1.5 || v < 0.67) ein.push(['!', 'Durchflussanzeige ' + g.Durchfluss_angezeigt_lh + ' l/h passt nicht zu Leistung und Spreizung (rechnerisch ca. ' + g.Durchfluss_rechnerisch_lh + ' l/h). Anzeige oder tatsächlichen Volumenstrom prüfen lassen.']);
      else ein.push(['+', 'Durchflussanzeige ' + g.Durchfluss_angezeigt_lh + ' l/h passt zu Leistung und Spreizung (rechnerisch ca. ' + g.Durchfluss_rechnerisch_lh + ' l/h).']);
    }
    if (g.AZ_Heizen !== null) {
      const txt = 'Arbeitszahl Heizen ' + fmt(g.AZ_Heizen) + ' im Zeitraum (Ø Außentemperatur ' + fmt(g.Aussen_C) + ' °C)';
      if (g.AZ_WW !== null && g.AZ_WW > g.AZ_Heizen) ein.push(['!', txt + ': niedriger als Warmwasser (' + fmt(g.AZ_WW) + '), Heiz-Vorlauf vermutlich zu hoch.']);
      else ein.push(['i', txt + '.']);
    }
    if (g.Mischer_Abw_K !== null && Math.abs(g.Mischer_Abw_K) > 2) ein.push(['!', 'Mischerkreis weicht im Mittel ' + fmt(g.Mischer_Abw_K) + ' K vom Soll ab.']);
    if (g.Mischer_ueber2K_Tag_Proz !== null && g.Mischer_ueber2K_Tag_Proz > 15) ein.push(['!', 'Mischerkreis tagsüber (6 bis 22 Uhr) in ' + g.Mischer_ueber2K_Tag_Proz + ' % der Minuten mehr als 2 K neben dem Soll (nachts ' + g.Mischer_ueber2K_Nacht_Proz + ' %).']);
    if (g.HUP_ohne_Verdichter_h !== null || g.ZUP_ohne_Verdichter_h !== null) {
      ein.push(['i', 'Pumpen in den Verdichterpausen: HUP ' + (g.HUP_ohne_Verdichter_h !== null ? fmt(g.HUP_ohne_Verdichter_h) : '–') + ' h, ZUP ' +
        (g.ZUP_ohne_Verdichter_h !== null ? fmt(g.ZUP_ohne_Verdichter_h) : '–') + ' h. Welche Pumpe welchen Kreis versorgt, hängt von der Hydraulik ab.']);
    }
    const offen = zyklen.filter(z => z.Status === 'Aus-Signal fehlt').length;
    if (g.Starts !== null && g.Starts > g.Starts_erkannt) ein.push(['i', (g.Starts - g.Starts_erkannt) + ' Starts nur im Zähler sichtbar (Läufe kürzer als das Abrufintervall oder Lücken).']);
    if (offen) ein.push(['i', offen + ' Läufe ohne Aus-Signal (Abrufintervall zu grob oder Lücke).']);
    if (g.Waerme_gesamt_kWh === null) ein.push(['', 'Wärmemenge ist aus „Heating capacity“ geschätzt. Genauer: Luxtronik per Modbus mitloggen (Menüpunkt 7).']);
    else ein.push(['', 'Strom, Wärme und Arbeitszahlen stammen aus den Zählern der Luxtronik (Modbus).']);

    return {
      deviceId, geraete, warnungen, start, ende, n, abgedeckt, alter, r, ID,
      tage: tagZeilen, gesamt: gesamtZeile, zyklen, aenderungen, proOffset: offsetZeilen,
      schaltpunkte, copNachVorlauf, einschaetzung: ein, zaehlerAb
    };
  }

  // CSV-Export der Ergebnisse (wie die Dateien des PowerShell-Scripts)
  function zuCsv(objekte, dezimal) {
    if (!objekte.length) return '';
    const keys = Object.keys(objekte[0]);
    const zelle = (k, v) => {
      if (v === null || v === undefined) return '';
      if ((k === 'Start' || k === 'Ende' || k === 'Erste_Heizminute' || k === 'Zeit') && typeof v === 'number') {
        const d = new Date(v);
        return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0') + ' ' +
          String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
      }
      if (typeof v === 'number') return String(v).replace('.', dezimal || ',');
      return String(v);
    };
    const q = s => '"' + String(s).replace(/"/g, '""') + '"';
    const zeilen = [keys.map(q).join(';')];
    for (const o of objekte) zeilen.push(keys.map(k => q(zelle(k, o[k]))).join(';'));
    return '﻿' + zeilen.join('\r\n') + '\r\n';
  }

  const api = { ID, parseCsv, analysiere, zuCsv, rnd, tagSchluessel, MIN };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.MuAuswertung = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
