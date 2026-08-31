// ALL-CAPS Spanish stop names → normal mixed case.
//
// Every feed here shouts its stop names ("5687 RIVADAVIA AV.") while the
// street names on the map come from OSM in proper case (Av. Rivadavia), and
// the two sit next to each other. Lowercasing is not a `toLowerCase()` away:
// half of the caps names drop their accents (CORDOBA, PERU, MORON), so the
// feed simply does not contain the information — but OSM does, properly
// written, in the very extracts the build already downloads: street names,
// squares, stations, schools. So we harvest a dictionary of accented word
// forms out of them and rewrite the caps names word by word through it
// (the Athens greek.mjs recipe, retold in Spanish). Whatever the dictionary
// does not know falls back to plain title case, which is at worst an
// unaccented — but readable — Spanish word.

// Accents live in the combining range; NFD + strip is the standard fold.
// (This folds Ñ to N on BOTH sides of the lookup, so ÑUÑEZ still finds Núñez.)
const norm = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase();
const UPPER = /[A-ZÀ-ÖØ-Þ]/;
const LOWER = /[a-zà-öø-ÿ]/;
// One word = one run of Latin letters. The apostrophe splits (O'HIGGINS is
// judged as O + HIGGINS, which title-cases each side on its own).
const WORD = /[A-Za-zÀ-ÖØ-Þà-öø-ÿ]+/g;

// A dictionary of accented word forms, harvested from every name in the OSM
// extracts. Words that appear in several spellings keep the commonest one.
export function buildNameDict(osmDocs) {
  const seen = new Map(); // folded word → Map(spelling → count)
  for (const doc of osmDocs) {
    for (const e of doc.elements || []) {
      const name = e.tags && e.tags.name;
      if (!name || !LOWER.test(name)) continue; // caps names teach us nothing
      for (const w of name.match(WORD) || []) {
        if (w.length < 3) continue;
        const k = norm(w);
        let m = seen.get(k);
        if (!m) seen.set(k, (m = new Map()));
        m.set(w, (m.get(w) || 0) + 1);
      }
    }
  }
  const dict = new Map();
  for (const [k, m] of seen) {
    let best = null, bestN = -1;
    for (const [w, n] of m) if (n > bestN) { best = w; bestN = n; }
    dict.set(k, best);
  }
  return dict;
}

// Particles: DE/DEL/Y go lowercase anywhere but the front of the name. The
// articles are the trap — "PLAZA DE LA REPUBLICA" wants "de la", but
// "AV. LA PLATA" wants "La Plata" — so LA/LAS/LOS/EL drop their capital ONLY
// right after a preposition, which is exactly how Spanish writes its own
// signs. Single-letter particles (Y, E, A, O) keep their capital at the END
// of a name, where they are a designator, not a conjunction ("RAMAL A").
const PREPS = new Set(['DE', 'DEL', 'Y', 'E', 'A', 'O', 'EN', 'AL', 'CASI']);
const ARTICLES = new Set(['LA', 'LAS', 'LOS', 'EL']);

const titleWord = (w) => w.charAt(0) + w.slice(1).toLowerCase();

// Rewrite one name, WORD BY WORD: a word that already carries a lowercase
// letter is left exactly as it is — that covers feeds (and single names) that
// write themselves properly.
export function latinTitleCase(name, dict, acronyms) {
  if (!name || !UPPER.test(name) || LOWER.test(name)) return name;
  // some feeds ship DECOMPOSED Unicode (Ñ as N + combining tilde), which would
  // split NUÑEZ into NUN|EZ at the combining mark — compose before splitting
  name = name.normalize('NFC');
  // the CABA feed loses every Ñ to a literal "?" (NU?EZ, ESPA?A, CASTA?ARES);
  // between two letters of an all-caps Spanish name that character can be
  // nothing else, and the dictionary then restores the accents on top
  name = name.replace(/([A-ZÀ-ÖØ-Þ])\?([A-ZÀ-ÖØ-Þ])/g, '$1Ñ$2');
  const toks = name.split(/(\s+)/);
  const words = toks.filter((t) => t && !/^\s+$/.test(t));
  let wi = -1, prevWord = '';
  return toks.map((tok) => {
    if (!tok || /^\s+$/.test(tok)) return tok;
    wi++;
    const prev = prevWord;
    prevWord = norm(tok).replace(/[^A-Z]/g, '') || prevWord;
    if (!UPPER.test(tok)) return tok; // digits, punctuation
    // a dotted initialism (S.A., F.F.C.C.) — every piece is an initial, so the
    // whole token stays as it is
    const pieces = tok.split('.').filter(Boolean);
    if (pieces.length > 1 && pieces.every((p) => p.replace(/[^A-ZÀ-ÖØ-Þ]/g, '').length <= 3)) return tok;
    const isLast = wi === words.length - 1;
    return tok.replace(WORD, (w, off) => {
      // ordinal tails ride their digit lowercase: "1RO" → "1ro", "25TA" → "25ta"
      if (off > 0 && /\d/.test(tok[off - 1]) && w.length >= 2) return w.toLowerCase();
      if (acronyms && acronyms.has(w)) return w;
      if (/^[IVX]+$/.test(w) && w.length >= 2) return w; // roman numerals (II, XV)
      const k = norm(w);
      if (wi > 0 && PREPS.has(k) && !(isLast && w.length === 1)) return w.toLowerCase();
      if (wi > 0 && ARTICLES.has(k) && PREPS.has(prev)) return w.toLowerCase();
      const known = dict && dict.get(k);
      return known ? titleWord(known) : titleWord(w);
    });
  }).join('');
}
