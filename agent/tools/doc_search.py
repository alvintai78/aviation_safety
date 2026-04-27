"""Document RAG tool — Azure AI Search via managed identity (no API keys)."""
from __future__ import annotations

import os
from typing import Any

from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizableTextQuery

_credential = DefaultAzureCredential(exclude_interactive_browser_credential=False)


def _client() -> SearchClient:
    endpoint = os.environ["SEARCH_ENDPOINT"]      # https://<svc>.search.windows.net
    index = os.environ["SEARCH_INDEX"]            # safety-docs
    return SearchClient(endpoint=endpoint, index_name=index, credential=_credential)


def doc_search(query: str, top_k: int = 5) -> dict[str, Any]:
    """Hybrid (keyword + vector) search over regulatory documents and past
    audit reports. Returns chunked passages with citations."""
    if not query or not query.strip():
        return {"results": []}
    client = _client()
    vector_query = VectorizableTextQuery(
        text=query,
        k_nearest_neighbors=top_k,
        fields="text_vector",
    )
    results = client.search(
        search_text=query,
        vector_queries=[vector_query],
        top=top_k,
        select=["chunk_id", "title", "page", "content", "source_url"],
        query_type="semantic",
        semantic_configuration_name="safety-docs-semantic",
    )
    out = []
    for r in results:
        out.append({
            "chunk_id": r.get("chunk_id"),
            "title": r.get("title"),
            "page": r.get("page"),
            "content": r.get("content"),
            "source_url": r.get("source_url"),
            "score": r.get("@search.score"),
            "reranker_score": r.get("@search.reranker_score"),
        })
    return {"results": out}
