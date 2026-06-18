import unittest

from sqlalchemy import select
from sqlalchemy.dialects import postgresql

from app.models import Comic
from app.services.comic_search import comic_search_filter, comic_search_order


def compile_sql(statement) -> str:
    return str(statement.compile(dialect=postgresql.dialect()))


class ComicSearchSqlTests(unittest.TestCase):
    def test_fuzzy_search_uses_trigram_similarity_and_prefix_fallback(self):
        sql = compile_sql(
            select(Comic.id)
            .where(comic_search_filter("immorttal"))
            .order_by(*comic_search_order("immorttal"))
            .limit(20)
        )

        self.assertIn("comics.title %%", sql)
        self.assertIn("similarity(lower(comics.title)", sql)
        self.assertIn("ILIKE", sql)
        self.assertIn("ORDER BY CASE", sql)


if __name__ == "__main__":
    unittest.main()
