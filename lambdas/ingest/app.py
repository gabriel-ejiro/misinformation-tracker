import os, time, json, hashlib
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
import boto3

DDB_TABLE = os.environ["TABLE_NAME"]
SOURCES = json.loads(os.environ.get("SOURCES_JSON", "[]"))
USE_COMPREHEND = os.environ.get("USE_COMPREHEND", "false").lower() == "true"

ddb = boto3.resource("dynamodb")
table = ddb.Table(DDB_TABLE)
comprehend = boto3.client("comprehend")

def _id(s):  # stable id from url+title
    return hashlib.sha1(s.encode("utf-8")).hexdigest()

def _now_iso():
    return datetime.now(timezone.utc).isoformat()

def fetch_rss(url, source):
    with urllib.request.urlopen(url, timeout=10) as r:
        xml = r.read()
    root = ET.fromstring(xml)
    items = []
    for item in root.iterfind(".//item"):
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        desc = (item.findtext("description") or "").strip()
        guid = link or title
        items.append({
            "source": source,
            "title": title[:500],
            "url": link,
            "summary": desc[:1000],
            "doc_id": _id(f"{source}:{guid}"),
        })
    return items

def analyze(txt):
    txt = (txt or "")[:4500]
    if not txt:
        return {"sentiment":"NEUTRAL","score":0.0,"keywords":[]}
    if USE_COMPREHEND:
        res = comprehend.detect_sentiment(Text=txt, LanguageCode="en")
        sent = res.get("Sentiment","NEUTRAL")
        score = max(res.get("SentimentScore",{}).values() or [0.0])
    else:
        # tiny heuristic fallback
        neg_words = ["fake","hoax","misleading","false","debunk"]
        score = sum(w in txt.lower() for w in neg_words)/5
        sent = "NEGATIVE" if score>=0.6 else "NEUTRAL"
    # naive keywords
    kws = [w for w in set(txt.lower().split()) if len(w)>6][:8]
    return {"sentiment":sent, "score":float(score), "keywords":kws}

def handler(event, context):
    total = 0
    for s in SOURCES:
        try:
            items = fetch_rss(s["url"], s["name"])
        except Exception as e:
            print(f"Fetch error {s}: {e}")
            continue
        for it in items[:50]:  # cap per run
            text = f"{it['title']} {it['summary']}"
            meta = analyze(text)
            record = {
                "pk": f"{it['source']}#{it['doc_id']}",
                "sk": int(time.time()),
                "source": it["source"],
                "title": it["title"],
                "url": it["url"],
                "summary": it["summary"],
                "sentiment": meta["sentiment"],
                "score": meta["score"],
                "keywords": meta["keywords"],
                "ingested_at": _now_iso(),
                "ttl": int(time.time()) + 60*60*24*30  # 30 days
            }
            table.put_item(Item=record)
            total += 1
    return {"ingested": total}
