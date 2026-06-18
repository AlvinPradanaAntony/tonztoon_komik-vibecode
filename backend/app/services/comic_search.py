import re

from sqlalchemy import case, func, or_

from app.models import Comic

_MIN_TOKEN_LENGTH = 3
_FUZZY_PREFIX_LENGTH = 4


def comic_search_filter(query: str):
    """Build a tolerant search predicate for comic title fields.

    The predicate keeps exact substring matches, adds pg_trgm indexed matches,
    and includes a conservative token-prefix fallback so light typos still find
    nearby titles.
    """
    clean_query = _clean_query(query)
    aliases = func.coalesce(Comic.alternative_titles, "")
    conditions = [
        Comic.title.ilike(f"%{clean_query}%"),
        aliases.ilike(f"%{clean_query}%"),
        Comic.title.op("%")(clean_query),
        aliases.op("%")(clean_query),
    ]

    for prefix in _fuzzy_prefixes(clean_query):
        pattern = f"%{prefix}%"
        conditions.extend([Comic.title.ilike(pattern), aliases.ilike(pattern)])

    return or_(*conditions)


def comic_search_order(query: str):
    """Rank search results by relevance before falling back to title order."""
    clean_query = _clean_query(query)
    aliases = func.coalesce(Comic.alternative_titles, "")
    title = func.lower(Comic.title)
    alias_text = func.lower(aliases)
    search_score = comic_search_score(clean_query)

    return (
        case(
            (title == clean_query, 0),
            (title.ilike(f"{clean_query}%"), 1),
            (Comic.title.ilike(f"%{clean_query}%"), 2),
            (alias_text.ilike(f"%{clean_query}%"), 3),
            else_=4,
        ),
        search_score.desc(),
        Comic.title.asc(),
    )


def comic_search_score(query: str):
    clean_query = _clean_query(query)
    aliases = func.coalesce(Comic.alternative_titles, "")
    title = func.lower(Comic.title)
    alias_text = func.lower(aliases)
    score_parts = [
        func.similarity(title, clean_query),
        func.similarity(alias_text, clean_query),
    ]

    for token in _tokens(clean_query):
        score_parts.extend(
            [
                func.similarity(title, token),
                func.similarity(alias_text, token),
            ]
        )

    return func.greatest(*score_parts)


def _clean_query(query: str) -> str:
    return re.sub(r"\s+", " ", query.casefold().strip())


def _tokens(query: str) -> list[str]:
    return [
        token
        for token in re.findall(r"[a-z0-9]+", query)
        if len(token) >= _MIN_TOKEN_LENGTH
    ]


def _fuzzy_prefixes(query: str) -> list[str]:
    prefixes = []
    for token in _tokens(query):
        if len(token) < _FUZZY_PREFIX_LENGTH:
            continue
        prefix = token[:_FUZZY_PREFIX_LENGTH]
        if prefix not in prefixes:
            prefixes.append(prefix)
    return prefixes
