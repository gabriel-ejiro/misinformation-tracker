import os, json, urllib.parse
import boto3
from boto3.dynamodb.conditions import Key

DDB_TABLE = os.environ["TABLE_NAME"]
ddb = boto3.resource("dynamodb")
table = ddb.Table(DDB_TABLE)

def _resp(status, body):
    return {"statusCode":status, "headers":{"content-type":"application/json"}, "body":json.dumps(body)}

def latest():
    # naive: scan last N seconds via sk index is ideal; here do small scan
    items = table.scan(Limit=50).get("Items", [])
    items.sort(key=lambda x: x["sk"], reverse=True)
    return items[:25]

def by_source(src):
    # if you add a GSI on "source", query it; for now, filter minimal set
    items = table.scan(Limit=200).get("Items", [])
    items = [i for i in items if i.get("source")==src]
    items.sort(key=lambda x: x["sk"], reverse=True)
    return items[:25]

def search(q):
    ql = q.lower()
    items = table.scan(Limit=300).get("Items", [])
    keep = []
    for i in items:
        text = f"{i.get('title','')} {i.get('summary','')}".lower()
        if ql in text:
            keep.append(i)
    keep.sort(key=lambda x: x["sk"], reverse=True)
    return keep[:25]

def handler(event, context):
    route = event.get("rawPath","/")
    params = event.get("queryStringParameters") or {}
    if route == "/latest":
        return _resp(200, latest())
    if route == "/by-source":
        src = params.get("name","")
        return _resp(200, by_source(src) if src else [])
    if route == "/search":
        q = params.get("q","")
        return _resp(200, search(q) if q else [])
    return _resp(404, {"error":"not found"})
