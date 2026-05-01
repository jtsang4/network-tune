#!/usr/bin/env python3
"""Generate a VLESS Reality share link from explicit fields."""

from __future__ import annotations

import argparse
from urllib.parse import quote, urlencode


def build_link(args: argparse.Namespace) -> str:
    params: dict[str, str] = {
        "encryption": args.encryption,
        "security": "reality",
        "sni": args.sni,
        "fp": args.fingerprint,
        "pbk": args.public_key,
        "sid": args.short_id,
        "type": args.transport,
    }
    if args.flow:
        params["flow"] = args.flow
    if args.alpn:
        params["alpn"] = args.alpn
    if args.spider_x:
        params["spx"] = args.spider_x

    query = urlencode(params, safe="/,:")
    name = quote(args.name, safe="")
    return f"vless://{args.uuid}@{args.host}:{args.port}?{query}#{name}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, help="Relay public IP or domain")
    parser.add_argument("--port", required=True, type=int, help="Relay public inbound port")
    parser.add_argument("--uuid", required=True, help="VLESS UUID")
    parser.add_argument("--sni", required=True, help="Reality SNI/server_name")
    parser.add_argument("--public-key", required=True, help="Reality public key")
    parser.add_argument("--short-id", required=True, help="Reality short ID")
    parser.add_argument("--name", required=True, help="Share link label")
    parser.add_argument("--flow", default="", help="Example: xtls-rprx-vision")
    parser.add_argument("--fingerprint", default="chrome", help="TLS fingerprint")
    parser.add_argument("--transport", default="tcp", help="Transport type")
    parser.add_argument("--encryption", default="none", help="VLESS encryption")
    parser.add_argument("--alpn", default="", help="Optional ALPN list")
    parser.add_argument("--spider-x", default="", help="Optional Reality spiderX path")
    print(build_link(parser.parse_args()))


if __name__ == "__main__":
    main()
