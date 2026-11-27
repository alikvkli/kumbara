#!/usr/bin/env python3
"""Commons'taki açık lisanslı gerçek fişleri indirir (yalnız CI'da). Görüntüler depoya girmez;
kaynak ve lisans bilgisi `*.truth.json` içine yazılır. Kullanıcıya/projeye ait bilgi gönderilmez:
genel bir User-Agent kullanılır."""
import json, os, sys, time, urllib.request
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
sources = json.load(open(os.path.join(os.path.dirname(__file__), "commons", "sources.json")))
for s in sources:
    req = urllib.request.Request(s["url"], headers={"User-Agent": "ReceiptOCRTestCorpus/1.0"})
    for attempt in range(4):
        try:
            data = urllib.request.urlopen(req, timeout=60).read()
            break
        except Exception as e:
            print(f"{s['name']}: {e}; tekrar"); time.sleep(5 * (attempt + 1))
    else:
        print(f"{s['name']}: indirilemedi"); continue
    open(os.path.join(out, s["name"] + ".jpg"), "wb").write(data)
    truth_path = os.path.join(os.path.dirname(__file__), "commons", s["name"] + ".truth.json")
    truth = json.load(open(truth_path)) if os.path.exists(truth_path) else {"kind": "?"}
    truth.update({"source": "commons", "license": s["license"], "attribution": s["attribution"], "url": s["page"],
                  "description": f"Wikimedia Commons, {s['license']}"})
    json.dump(truth, open(os.path.join(out, s["name"] + ".truth.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{s['name']}: {len(data)} bayt")
    time.sleep(3)
