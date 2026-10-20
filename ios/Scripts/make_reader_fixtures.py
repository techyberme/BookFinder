"""Builds anonymised "área del lector" fixtures from pages saved in a browser while logged in.

Usage (from the repo root):
    python3 ios/Scripts/make_reader_fixtures.py <dir with saved pages>

Expects two pages saved from the OPAC while logged in:
    Trasiniciarsesion.html  the page shown right after "Identifícame"
    prestamos.html          "Mi biblioteca" (ACC=210)

Personal data is removed by *structure* (whole sections), never by listing the user's values here,
so this script is safe to commit. It then fails if anything that looks like personal data survives.
Browsers often save these ISO-8859-1 pages as UTF-8 with accents replaced by U+FFFD; accents are
restored from the vocabulary of the public fixtures, and the output is written as ISO-8859-1 like
the live site.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIX = ROOT / "ios/ZahoriKit/Tests/ZahoriKitTests/Fixtures"
FAKE_NAME = "Lectora Prueba"

# Sections of Mi biblioteca that hold personal data: reader card, its details modal, password, e-mail, alias.
PERSONAL_SECTIONS = [r'<section id="lector_data"', r'<div class="lector_camp\b', r'<div id="lector_CP"', r'<div id="lector_CE"', r'<div id="lector_CA"']


def remove_element(html: str, start_pattern: str) -> str:
    """Removes the element starting at `start_pattern`, matching nested tags of the same name."""
    m = re.search(start_pattern, html)
    if not m:
        return html
    tag = re.match(r"<(\w+)", html[m.start():]).group(1)
    depth, pos = 0, m.start()
    for t in re.finditer(rf"<(/?){tag}\b[^>]*>", html[m.start():]):
        depth += -1 if t.group(1) else 1
        if depth == 0:
            pos = m.start() + t.end()
            break
    return html[: m.start()] + html[pos:]


def anonymise(html: str) -> str:
    for start in PERSONAL_SECTIONS:
        html = remove_element(html, start)
    # Reader name / alias in the header and the side panel ("Área identificada del lector").
    for cls in ("icm_lectorDisconnectCont", "icm_lectorDisconnectCont2", "lector_lenlec"):
        html = re.sub(rf'(<(\w+)[^>]*class="[^"]*{cls}[^"]*"[^>]*>)(.*?)(</\2>)',
                      lambda m: m.group(1) + FAKE_NAME + m.group(4), html, flags=re.S)
    # Name / initials on the "Mi biblioteca" header button (short and long variants).
    html = re.sub(r'(<span class="q-hd--(?:lt-md|gt-sm)">)[^<]*(</span>)', rf"\g<1>{FAKE_NAME}\2", html)
    # Reader number wherever it is printed ("Nº lector: …").
    html = re.sub(r"(N\W{1,2}\s*lector:\s*)(<[^>]+>\s*)*[^<\s]+", r"\g<1>0000000", html)
    return html


def assert_no_personal_data(name: str, html: str) -> None:
    text = re.sub(r"<[^>]+>", " ", html)
    problems = []
    if re.search(r"[\w.+-]+@[\w-]+\.[\w.]+", html):
        problems.append("e-mail address")
    if re.search(r"\b[6789]\d{8}\b", text):
        problems.append("phone-like number")
    if re.search(r"\b\d{8}[A-Za-z]\b|\bxx[A-Z]\b", text):
        problems.append("DNI-like value")
    for year in re.findall(r"\b\d{2}/\d{2}/(\d{4})\b", text):
        if int(year) < 2015:
            problems.append(f"old date ({year}): birth date?")
    for label in ("Nacimiento", "DNI", "Tel�fono", "Teléfono", "E-mail", "Apellidos"):
        if label in text:
            problems.append(f"label {label!r}")
    if problems:
        sys.exit(f"{name}: personal data still present: {sorted(set(problems))}")


def accent_vocabulary() -> dict:
    """Words with non-ASCII letters taken from the public (correctly encoded) fixtures."""
    vocab = {}
    for f in FIX.glob("opac_*.html"):
        for w in re.findall(r"[^\W\d_]+", f.read_text(encoding="latin-1")):
            if any(ord(c) > 127 for c in w):
                key = re.sub(r"[^\x00-\x7f]", "�", w)
                vocab.setdefault(key, set()).add(w)
    # Words that only appear in the reader area.
    extra = ["Préstamos", "préstamo", "préstamos", "Histórico", "devolución", "Renovación", "días", "límite",
             "Acuña", "adquisición", "Área", "contraseña", "Contraseña", "búsquedas", "Búsquedas", "electrónico",
             "Información", "sesión", "Menú", "más", "Más", "Catálogos", "información", "sugerencias", "Añadir",
             "Descripción", "Búsqueda", "Gestión", "Dirección", "Código", "Códigos", "nº", "Nº", "opción"]
    for w in extra:
        vocab.setdefault(re.sub(r"[^\x00-\x7f]", "�", w), set()).add(w)
    return vocab


def restore_accents(html: str, vocab: dict) -> tuple:
    unresolved = set()

    def fix(m):
        w = m.group(0)
        options = vocab.get(w, set())
        if len(options) == 1:
            return next(iter(options))
        unresolved.add(w)
        return w

    html = re.sub(r"[^\W\d_]*�[^\W\d_�]*(?:�[^\W\d_�]*)*", fix, html)
    # Anything left: a neutral placeholder so the file is valid ISO-8859-1.
    return html.replace("�", "?"), unresolved


def first_loan(html: str) -> str:
    return re.search(r'<li id="lector_box\d+".*?</li>', html, re.S).group(0)


def variant(li, barcode, title, branch, due, loan_date, sign, used, max_ren, window, resv, titn):
        """Rewrites every value of one loan <li>, keeping the markup exactly as the OPAC sends it."""
        v = li
        v = re.sub(r"TITN=\d+", f"TITN={titn}", v)
        v = re.sub(r"lector_box\d+|data-prbarc=\"\d+\"|lector_renovMen\d+|lector_addTocal\d+",
                   lambda m: re.sub(r"\d+", barcode, m.group(0)), v)
        v = re.sub(r'(<span class="prbarc">)\d+', rf"\g<1>{barcode}", v)
        v = re.sub(r"(<span>)[^<]*( /</span>)", rf"\g<1>{title}\2", v, count=1)
        v = re.sub(r'(<span class="tititu">)[^<]*', rf"\g<1>{title} /", v)
        v = re.sub(r'(<span class="description">)[^<]*', rf"\g<1>{branch}", v)
        v = re.sub(r'(<span class="prfdev">)[^<]*', rf"\g<1>{due} 23:59", v)
        v = re.sub(r"(Fecha de devoluci.n: )\d{2}/\d{2}/\d{4}", rf"\g<1>{due}", v)
        v = re.sub(r'(<span class="prnren">)\d+', rf"\g<1>{used}", v)
        v = re.sub(r'(<span class="ppdrnm">)\d+', rf"\g<1>{max_ren}", v)
        v = re.sub(r'(<span class="ppdrna">)\d+', rf"\g<1>{window}", v)
        v = re.sub(r'(<span class="xsresv">)\d+', rf"\g<1>{resv}", v)
        v = re.sub(r'(<span class="t-we--500">)\d+ / \d+', rf"\g<1>{used} / {max_ren}", v)
        v = re.sub(r'(lector_boxDataInfoTxt">)\d{2}/\d{2}/\d{4} \d{2}:\d{2}', rf"\g<1>{loan_date}", v)
        v = re.sub(r"(<span>)N [^<]*(</span>\s*</span>)", rf"\g<1>{sign}\2", v)
        v = re.sub(r"(<span>)[^<]*(</span>\s*</button>)", rf"\g<1>{branch}\2", v)
        v = re.sub(r"(<span>)[^<]*(</span>\s*</a>\s*</p>\s*<p>\s*<span class=\"lector_boxDataInfoLbl\">Fecha)",
                   rf"\g<1>{branch}\2", v)
        return v


def synthetic_variants(loans_html: str) -> dict:
    """Extra fixtures derived from the real structure: no loans, and three loans."""
    li = first_loan(loans_html)
    empty = loans_html.replace(li, "")
    extra = [
        variant(li, "2000999001", "Ficciones", "RETIRO. BP Eugenio Trías", "25/10/2026", "25/09/2026 11:02", "N BOR fic", 1, 1, 5, 0, 1000001),
        variant(li, "2000999002", "El infinito en un junco : la invención de los libros en el mundo antiguo",
                "CHAMARTÍN. BP Dámaso Alonso", "02/11/2026", "03/10/2026 18:30", "82-4 VAL inf", 0, 2, 5, 3, 1000002),
    ]
    multi = loans_html.replace(li, li + "\n" + "\n".join(extra))
    return {"lector_loans_empty.html": empty, "lector_loans_multi.html": multi}


def main(src: str) -> None:
    src_dir = Path(src)
    vocab = accent_vocabulary()
    outputs = {}
    for source, target in (("Trasiniciarsesion.html", "lector_post_login.html"), ("prestamos.html", "lector_loans.html")):
        html = (src_dir / source).read_text(encoding="utf-8")
        html = anonymise(html)
        if re.search(r'<li id="lector_box', html):
            # The user's real loan is reading history: replace it with a fictional one.
            li = first_loan(html)
            html = html.replace(li, variant(li, "2000000001", "Rayuela", "MONCLOA-ARAVACA. BP Acuña", "12/11/2026",
                                            "13/10/2026 16:45", "N COR ray", 0, 1, 5, 0, 1000000))
        html, unresolved = restore_accents(html, vocab)
        if unresolved:
            print(f"{target}: {len(unresolved)} words left with '?': {sorted(unresolved)[:15]}")
        outputs[target] = html
    outputs.update(synthetic_variants(outputs["lector_loans.html"]))

    for name, html in outputs.items():
        assert_no_personal_data(name, html)
        (FIX / name).write_bytes(html.encode("latin-1"))
        print("wrote", FIX / name)


if __name__ == "__main__":
    main(sys.argv[1])
