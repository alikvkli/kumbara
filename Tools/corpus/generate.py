#!/usr/bin/env python3
"""Kumbara yakalama korpusu üreticisi (specs/04 §6, T3.1).

Türk fiş / e-arşiv / banka ekranı / SMS biçimlerinde görüntüler ve doğru cevaplarını
(`*.truth.json`) üretir. Görüntüler CI'da gerçek Apple Vision OCR'ından geçirilir
(`kumbara-ocr`); böylece korpusa Vision'ın gerçek hataları girer, etiket ise kesin doğrudur.

Kullanım: python3 generate.py <çıktı-klasörü> [--count-scale 1] [--seed 2026]
"""
import argparse, json, math, os, random
from datetime import datetime, timedelta, timezone
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance

TZ = timezone(timedelta(hours=3))
NOW = datetime(2026, 11, 27, 18, 0, tzinfo=TZ)
MONTHS = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]

FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/liberation", "/usr/share/fonts/truetype/liberation2"]
def font_path(name):
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p): return p
    return None
MONO = [f for f in [font_path("DejaVuSansMono.ttf"), font_path("LiberationMono-Regular.ttf")] if f]
MONO_BOLD = [f for f in [font_path("DejaVuSansMono-Bold.ttf"), font_path("LiberationMono-Bold.ttf")] if f]
SANS = [f for f in [font_path("DejaVuSans.ttf"), font_path("LiberationSans-Regular.ttf")] if f]
SANS_BOLD = [f for f in [font_path("DejaVuSans-Bold.ttf"), font_path("LiberationSans-Bold.ttf")] if f]
assert MONO and SANS, "DejaVu veya Liberation fontları gerekli"

def tl(value, star=False, suffix=False, sign=""):
    s = f"{value:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return f"{sign}{'*' if star else ''}{s}{' TL' if suffix else ''}"

def rand_date(r, max_days=60):
    d = NOW - timedelta(days=r.randint(0, max_days), hours=r.randint(0, 9), minutes=r.randint(0, 59))
    return d.replace(second=0, microsecond=0)

def fmt_date(r, d):
    style = r.choice(["dot", "dot", "slash", "dash"])
    return {"dot": d.strftime("%d.%m.%Y"), "slash": d.strftime("%d/%m/%Y"), "dash": d.strftime("%d-%m-%Y")}[style]

# ---------- çizim ----------

class Paper:
    def __init__(self, r, width, mono=True):
        self.r = r
        self.w = width
        size = r.randint(22, 28)
        self.font = ImageFont.truetype(r.choice(MONO if mono else SANS), size)
        self.bold = ImageFont.truetype(r.choice(MONO_BOLD if mono else SANS_BOLD), int(size * 1.25))
        self.lines = []  # (kind, a, b, bold)
        self.lh = int(size * r.uniform(1.35, 1.6))

    def center(self, t, bold=False): self.lines.append(("c", t, None, bold))
    def row(self, a, b="", bold=False): self.lines.append(("r", a, b, bold))
    def cols(self, a, mid, b): self.lines.append(("3", a, (mid, b), False))
    def rule(self): self.lines.append(("-", None, None, False))
    def gap(self): self.lines.append((" ", None, None, False))

    def render(self):
        h = 60 + sum(self.lh * (1.3 if l[3] else 1) for l in self.lines) + 80
        img = Image.new("L", (self.w, int(h)), 250)
        d = ImageDraw.Draw(img)
        y, m = 40, 36
        ink = self.r.randint(10, 45)
        for kind, a, b, bold in self.lines:
            f = self.bold if bold else self.font
            if kind == "c":
                d.text(((self.w - d.textlength(a, font=f)) / 2, y), a, fill=ink, font=f)
            elif kind == "r":
                d.text((m, y), a, fill=ink, font=f)
                if b: d.text((self.w - m - d.textlength(b, font=f), y), b, fill=ink, font=f)
            elif kind == "3":
                d.text((m, y), a, fill=ink, font=f)
                d.text((int(self.w * 0.6), y), b[0], fill=ink, font=f)
                d.text((self.w - m - d.textlength(b[1], font=f), y), b[1], fill=ink, font=f)
            elif kind == "-":
                d.line((m, y + self.lh // 2, self.w - m, y + self.lh // 2), fill=130, width=2)
            y += int(self.lh * (1.3 if bold else 1))
        return img

def photograph(r, img, max_angle=2.5):
    """Kağıdı fotoğraflanmış gibi yap: doku, solma, bulanıklık, eğim, arka plan."""
    px = img.load()
    for _ in range(int(img.width * img.height * r.uniform(0.004, 0.02))):
        x, y = r.randrange(img.width), r.randrange(img.height)
        px[x, y] = max(0, px[x, y] - r.randrange(15, 70))
    if r.random() < 0.35:  # solmuş termal baskı
        img = ImageEnhance.Contrast(img).enhance(r.uniform(0.45, 0.75))
        img = ImageEnhance.Brightness(img).enhance(r.uniform(1.05, 1.2))
    img = img.filter(ImageFilter.GaussianBlur(r.uniform(0.2, 1.1)))
    bg = r.randint(120, 215)
    pad = r.randint(30, 90)
    canvas = Image.new("L", (img.width + 2 * pad, img.height + 2 * pad), bg)
    canvas.paste(img, (pad, pad))
    canvas = canvas.rotate(r.uniform(-max_angle, max_angle), resample=Image.BICUBIC, fillcolor=bg)
    return canvas.convert("RGB")

# ---------- şablonlar ----------

CHAINS = [
    ("MİGROS TİC. A.Ş.", "Migros"), ("BİM BİRLEŞİK MAĞAZALAR A.Ş.", "BİM"), ("A101 YENİ MAĞAZACILIK A.Ş.", "A101"),
    ("ŞOK MARKETLER TİC. A.Ş.", "Şok"), ("CARREFOURSA CARREFOUR SABANCI TİC. MRK. A.Ş.", "CarrefourSA"),
    ("MACROCENTER", "Macrocenter"), ("HAKMAR MAĞAZACILIK", "Hakmar"), ("FILE MARKET", "File"),
]
GROCERIES = [("SÜT 1L", 42.5), ("EKMEK", 15), ("YUMURTA 30'LU", 189.9), ("BEYAZ PEYNİR", 239.9), ("ZEYTİN 500G", 164.5),
             ("DOMATES KG", 34.9), ("SALATALIK KG", 29.9), ("MAKARNA", 24.95), ("PİRİNÇ 1KG", 79.9), ("ÇAY 1KG", 289),
             ("DETERJAN 4KG", 802.5), ("TUVALET KAĞIDI", 249.9), ("ZEYTİNYAĞI 1L", 389.9), ("SU 5L", 39.9), ("YOĞURT", 74.5)]
ADDRESSES = ["ATAŞEHİR MAH. ATATÜRK CAD. NO:12", "KOŞUYOLU MAH. BAĞDAT CAD. NO:255", "ESENTEPE MAH. BÜYÜKDERE CAD. NO:4",
             "KIZILAY MAH. ATATÜRK BLV. NO:88", "ALSANCAK MAH. KIBRIS ŞEHİTLERİ CAD. NO:31"]

def header(p, r, name, d):
    p.center(name, bold=True)
    p.center(r.choice(ADDRESSES))
    if r.random() < 0.7: p.center(f"TEL: 0{r.randint(212, 488)} {r.randint(100, 999)} {r.randint(10, 99)} {r.randint(10, 99)}")
    if r.random() < 0.6: p.center(f"V.D. {r.choice(['KOZYATAĞI', 'MECİDİYEKÖY', 'ÇANKAYA', 'KARŞIYAKA'])} {r.randint(10**9, 10**10 - 1)}")
    p.gap()
    date_text = fmt_date(r, d)
    if r.random() < 0.6:
        p.row(f"TARİH : {date_text}", f"SAAT : {d:%H:%M}")
    else:
        p.row(date_text, d.strftime("%H:%M"))
    p.row(f"FİŞ NO : {r.randint(1, 9999):04d}")
    p.rule()

def footer(p, r, total, star):
    pay = r.choice(["KREDİ KARTI", "NAKİT", "BANKA KARTI", None])
    if pay: p.row(pay, tl(total, star))
    p.gap()
    p.row(f"Z NO: {r.randint(1, 999):04d}", f"EKÜ NO: {r.randint(1, 9):04d}")
    if r.random() < 0.5: p.center("TEŞEKKÜR EDERİZ")
    p.center(f"MF {r.choice(['YAB', 'JH', 'AT'])} {r.randint(10**7, 10**8 - 1)}")

def market(r):
    legal, display = r.choice(CHAINS)
    d = rand_date(r)
    p = Paper(r, r.randint(600, 760), mono=r.random() < 0.85)
    header(p, r, legal, d)
    star = r.random() < 0.7
    items = r.sample(GROCERIES, r.randint(2, 8))
    total = 0
    for name, price in items:
        qty = r.choice([1, 1, 1, 2, 3])
        line = round(price * qty, 2)
        total += line
        label = f"{qty} X {name}" if qty > 1 else name
        p.cols(label, r.choice(["%1", "%10", "%20"]), tl(line, star))
    total = round(total, 2)
    p.rule()
    p.row("TOPKDV", tl(round(total * 0.09, 2), star))
    p.row(r.choice(["TOPLAM", "TOPLAM", "GENEL TOPLAM", "TOPLAM TUTAR"]), tl(total, star), bold=True)
    footer(p, r, total, star)
    return p.render(), {"kind": "receipt", "amount": f"{total:.2f}", "merchant": display,
                        "date": d.strftime("%Y-%m-%dT%H:%M"), "category": "market.food"}

def fuel(r):
    legal, display = r.choice([("OPET PETROLCÜLÜK A.Ş.", "Opet"), ("SHELL & TURCAS PETROL A.Ş.", "Shell"),
                               ("PETROL OFİSİ A.Ş.", "Petrol Ofisi"), ("AYTEMİZ AKARYAKIT", "Aytemiz")])
    d = rand_date(r)
    p = Paper(r, r.randint(600, 720))
    header(p, r, legal, d)
    star = r.random() < 0.7
    unit = round(r.uniform(48, 56), 2)
    total = float(r.choice([500, 750, 1000, 1500, 2000, 2500]))
    litres = round(total / unit, 2)
    p.row(r.choice(["MOTORİN", "KURŞUNSUZ 95", "BENZİN"]), tl(total, star))
    p.row(f"{litres:.2f} LT X {unit:.2f}".replace(".", ","))
    p.rule()
    p.row("KDV", tl(round(total / 6, 2), star))
    p.row("TOPLAM", tl(total, star), bold=True)
    footer(p, r, total, star)
    return p.render(), {"kind": "receipt", "amount": f"{total:.2f}", "merchant": display,
                        "date": d.strftime("%Y-%m-%dT%H:%M"), "category": "transport.fuel"}

def restaurant(r):
    name, display, cat = r.choice([("KÖFTECİ YUSUF", "Köfteci Yusuf", "dining.restaurant"),
                                   ("BURGER KING", "Burger King", "dining.restaurant"),
                                   ("DOMINOS PIZZA", "Domino's", "dining.restaurant"),
                                   ("ANADOLU SOFRASI LOKANTA", None, "dining.restaurant"),
                                   ("KARADENİZ PİDE RESTORAN", None, "dining.restaurant")])
    d = rand_date(r)
    p = Paper(r, r.randint(600, 720), mono=r.random() < 0.6)
    p.center(name, bold=True); p.center(r.choice(ADDRESSES)); p.gap()
    p.row(f"Tarih: {fmt_date(r, d)} Saat: {d:%H:%M}")
    p.rule()
    sub = 0
    for item, price in r.sample([("Köfte Porsiyon", 270), ("Ayran", 40), ("Pide", 220), ("Lahmacun", 120),
                                 ("Çorba", 110), ("Künefe", 180), ("Kola", 60), ("Salata", 95)], r.randint(2, 5)):
        q = r.choice([1, 1, 2])
        sub += price * q
        p.row(f"{q} x {item}", tl(price * q))
    p.rule()
    p.row("ARA TOPLAM", tl(sub))
    disc = round(sub * r.choice([0, 0, 0.1]), 2)
    if disc: p.row("İNDİRİM", tl(disc, sign="-"))
    service = round((sub - disc) * r.choice([0, 0.1]), 2)
    if service: p.row("SERVİS", tl(service))
    total = round(sub - disc + service, 2)
    p.row("KDV %10", tl(round(total / 11, 2)))
    p.row("GENEL TOPLAM", tl(total), bold=True)
    truth = {"kind": "receipt", "amount": f"{total:.2f}", "date": d.strftime("%Y-%m-%dT%H:%M"), "category": cat}
    if display: truth["merchant"] = display
    return p.render(), truth

def cafe(r):
    name, display = r.choice([("STARBUCKS COFFEE", "Starbucks"), ("KAHVE DÜNYASI", "Kahve Dünyası"), ("ESPRESSOLAB", "Espressolab")])
    d = rand_date(r)
    p = Paper(r, r.randint(520, 640), mono=r.random() < 0.5)
    p.center(name, bold=True); p.center(r.choice(["ZORLU AVM", "KANYON AVM", "MODA", "BEŞİKTAŞ"]))
    p.row(f"{fmt_date(r, d)} {d:%H:%M}")
    total = 0
    for item, price in r.sample([("Latte Grande", 185), ("Americano", 150), ("Filtre Kahve", 120), ("Kurabiye", 95),
                                 ("Cheesecake", 210)], r.randint(1, 3)):
        total += price
        p.row(item, tl(price))
    p.rule()
    narrow = r.random() < 0.3  # dar fiş: tutar alt satıra kayar
    if narrow:
        p.row("TOPLAM", bold=True); p.row("", tl(total), bold=True)
    else:
        p.row("TOPLAM", tl(total), bold=True)
    return p.render(), {"kind": "receipt", "amount": f"{total:.2f}", "merchant": display,
                        "date": d.strftime("%Y-%m-%dT%H:%M"), "category": "dining.cafe"}

def pharmacy(r):
    owner = r.choice(["YILDIZ", "ŞİFA", "HAYAT", "MERKEZ", "GÜNEŞ"])
    d = rand_date(r)
    p = Paper(r, r.randint(560, 680))
    p.center(f"{owner} ECZANESİ", bold=True); p.center(r.choice(ADDRESSES)); p.gap()
    p.row(fmt_date(r, d), d.strftime("%H:%M")); p.rule()
    total = 0
    for _ in range(r.randint(1, 3)):
        price = round(r.uniform(45, 420), 2); total += price
        p.row(r.choice(["İLAÇ", "VİTAMİN", "KREM", "AĞRI KESİCİ"]), tl(price))
    total = round(total, 2)
    p.rule(); p.row("TOPLAM", tl(total), bold=True)
    return p.render(), {"kind": "receipt", "amount": f"{total:.2f}", "date": d.strftime("%Y-%m-%dT%H:%M"),
                        "category": "health.pharmacy"}

def earsiv(r):
    company, display, cat = r.choice([("ENERJİSA İSTANBUL ANADOLU YAKASI ELEKTRİK PERAKENDE SATIŞ A.Ş.", "Enerjisa", "housing.electricity"),
                                      ("TURKCELL İLETİŞİM HİZMETLERİ A.Ş.", "Turkcell", "housing.internet"),
                                      ("İGDAŞ İSTANBUL GAZ DAĞITIM A.Ş.", "İGDAŞ", "housing.gas")])
    d = rand_date(r)
    p = Paper(r, 900, mono=False)
    p.center("e-Arşiv Fatura", bold=True); p.gap()
    p.row(company); p.row(r.choice(ADDRESSES)); p.gap()
    p.row(f"Fatura Tarihi: {d.day} {MONTHS[d.month - 1]} {d.year}")
    p.row(f"ETTN: {r.getrandbits(32):08x}-{r.getrandbits(16):04x}-{r.getrandbits(16):04x}-{r.getrandbits(48):012x}")
    p.gap()
    net = round(r.uniform(250, 1800), 2); vat = round(net * 0.2, 2); total = round(net + vat, 2)
    p.row("Mal Hizmet Toplam Tutarı", tl(net, suffix=True))
    p.row("Hesaplanan KDV (%20)", tl(vat, suffix=True))
    p.row("Vergiler Dahil Toplam Tutar", tl(total, suffix=True))
    p.row("Ödenecek Tutar", tl(total, suffix=True), bold=True)
    img = p.render().convert("RGB")
    if r.random() < 0.5: img = photograph(r, img.convert("L"), 1.5)
    return img, {"kind": "receipt", "amount": f"{total:.2f}", "merchant": display,
                 "date": d.strftime("%Y-%m-%d"), "category": cat}

def bank_screen(r):
    """Banka uygulaması hareket listesi ekran görüntüsü (düz, eğiksiz, keskin)."""
    W, H = 1179, 2556
    img = Image.new("RGB", (W, H), (248, 248, 250) if r.random() < 0.6 else (18, 18, 20))
    dark = img.getpixel((0, 0))[0] < 100
    fg, sec = ((235, 235, 235), (150, 150, 155)) if dark else ((20, 20, 22), (120, 120, 128))
    d = ImageDraw.Draw(img)
    big = ImageFont.truetype(r.choice(SANS_BOLD), 56); f = ImageFont.truetype(r.choice(SANS), 44)
    small = ImageFont.truetype(r.choice(SANS), 36)
    y = 180
    d.text((60, y), "Hesap Hareketleri", fill=fg, font=big); y += 110
    d.text((60, y), f"Kullanılabilir Bakiye {tl(r.uniform(2000, 40000), suffix=True)}", fill=sec, font=small); y += 120
    drafts = []
    pool = [("MİGROS ATAŞEHİR", "Migros", "market.food"), ("OPET KADIKÖY", "Opet", "transport.fuel"),
            ("NETFLIX.COM", "Netflix", "subscriptions"), ("A101 MODA", "A101", "market.food"),
            ("STARBUCKS ZORLU", "Starbucks", "dining.cafe"), ("TURKCELL FATURA", "Turkcell", "housing.internet"),
            ("YEMEKSEPETI", "Yemeksepeti", "dining.delivery"), ("SHELL MASLAK", "Shell", "transport.fuel")]
    day = NOW - timedelta(days=r.randint(0, 5))
    for _ in range(r.randint(2, 3)):
        d.text((60, y), f"{day.day} {MONTHS[day.month - 1]} {day.year}", fill=sec, font=small); y += 80
        for _ in range(r.randint(1, 3)):
            if r.random() < 0.2:
                name, display, cat, sign, amount = "FAST GELEN TRANSFER", None, None, "+", round(r.uniform(500, 8000), 2)
            else:
                name, display, cat = r.choice(pool); sign, amount = "-", round(r.uniform(40, 2500), 2)
            d.text((60, y), name, fill=fg, font=f)
            text = tl(amount, suffix=True, sign=sign)
            d.text((W - 60 - d.textlength(text, font=f), y), text, fill=(40, 160, 80) if sign == "+" else fg, font=f)
            y += 110
            draft = {"amount": f"{amount:.2f}", "kind": "income" if sign == "+" else "expense", "date": day.strftime("%Y-%m-%d")}
            if display: draft["merchant"] = display
            if cat: draft["category"] = cat
            drafts.append(draft)
        day -= timedelta(days=r.randint(1, 2))
        y += 30
    img = img.resize((W // 2, H // 2), Image.LANCZOS)  # ekran görüntüsü ölçeği
    return img, {"kind": "bankList", "drafts": drafts}

def sms(r):
    W, H = 1179, 1400
    img = Image.new("RGB", (W, H), (255, 255, 255)); d = ImageDraw.Draw(img)
    f = ImageFont.truetype(r.choice(SANS), 42)
    legal, display = r.choice([("A101 YENİ MAĞAZACILIK", "A101"), ("MİGROS TİC", "Migros"), ("OPET PETROLCÜLÜK", "Opet"),
                               ("STARBUCKS", "Starbucks")])
    cat = {"A101": "market.food", "Migros": "market.food", "Opet": "transport.fuel", "Starbucks": "dining.cafe"}[display]
    dt = rand_date(r, 10); amount = round(r.uniform(30, 3000), 2)
    d.rounded_rectangle((40, 200, W - 160, 200 + 4 * 62 + 60), 40, fill=(233, 233, 235))
    lines = [f"Kartınızdan {dt:%d.%m.%Y %H:%M} tarihinde", f"{legal} işyerinde {tl(amount, suffix=True)}",
             "tutarında harcama yapılmıştır.", "Bankam"]
    for i, line in enumerate(lines):
        d.text((80, 230 + i * 62), line, fill=(20, 20, 20), font=f)
    img = img.resize((W // 2, H // 2), Image.LANCZOS)
    return img, {"kind": "notification", "amount": f"{amount:.2f}", "merchant": display,
                 "date": dt.strftime("%Y-%m-%dT%H:%M"), "category": cat}

PLAN = [(market, 14), (fuel, 6), (restaurant, 6), (cafe, 5), (pharmacy, 4), (earsiv, 4), (bank_screen, 5), (sms, 5)]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out"); ap.add_argument("--seed", type=int, default=2026); ap.add_argument("--count-scale", type=float, default=1)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    r = random.Random(a.seed)
    n = 0
    for fn, count in PLAN:
        for i in range(max(1, int(count * a.count_scale))):
            img, truth = fn(r)
            if fn not in (bank_screen, sms, earsiv):
                img = photograph(r, img.convert("L"))
            name = f"{fn.__name__}-{i + 1:02d}"
            img.save(os.path.join(a.out, name + ".jpg"), quality=r.randint(70, 92))
            truth.update({"source": "vision-synthetic", "generator": "Tools/corpus/generate.py", "seed": a.seed,
                          "now": NOW.isoformat(), "description": f"{fn.__name__} şablonu, üretilmiş"})
            json.dump(truth, open(os.path.join(a.out, name + ".truth.json"), "w"), ensure_ascii=False, indent=1)
            n += 1
    print(f"{n} görüntü üretildi → {a.out}")

if __name__ == "__main__":
    main()
