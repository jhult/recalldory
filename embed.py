#!/usr/bin/env python3
"""
Embedding generator for inko-recall using sentence-transformers.
Uses nomic-embed-text-v1.5 model for generating 768-dimensional embeddings.

Usage:
    echo "text to embed" | python3 embed.py
    python3 embed.py "text to embed"
"""

import sys
import json

def get_embedding(text: str) -> list[float]:
    """Generate embedding for the given text."""
    try:
        from sentence_transformers import SentenceTransformer
    except ImportError:
        print("Error: sentence_transformers not installed", file=sys.stderr)
        print("Run: pip install sentence-transformers", file=sys.stderr)
        sys.exit(1)

    # Load model (will download on first use)
    model = SentenceTransformer("nomic-ai/nomic-embed-text-v1.5", trust_remote_code=True)

    # Generate embedding with task prefix
    prefixed_text = f"search_document: {text}"
    embedding = model.encode(prefixed_text, normalize_embeddings=True)

    return embedding.tolist()

def main():
    if len(sys.argv) > 1:
        text = " ".join(sys.argv[1:])
    else:
        text = sys.stdin.read().strip()

    if not text:
        print("Error: No text provided", file=sys.stderr)
        sys.exit(1)

    embedding = get_embedding(text)

    # Output as JSON array
    print(json.dumps(embedding))

if __name__ == "__main__":
    main()
