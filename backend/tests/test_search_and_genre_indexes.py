import unittest

from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateIndex

from app.models import Comic, comic_genre


def compile_index(index_name: str) -> str:
    index = next(index for index in Comic.__table__.indexes if index.name == index_name)
    return str(CreateIndex(index).compile(dialect=postgresql.dialect()))


class SearchAndGenreIndexTests(unittest.TestCase):
    def test_comic_search_trigram_indexes_are_declared(self):
        index_names = {index.name for index in Comic.__table__.indexes}
        self.assertIn("ix_comics_title_trgm", index_names)
        self.assertIn("ix_comics_alternative_titles_trgm", index_names)

    def test_comic_search_trigram_indexes_use_gin_ops(self):
        title_sql = compile_index("ix_comics_title_trgm")
        alternative_sql = compile_index("ix_comics_alternative_titles_trgm")
        self.assertIn("USING gin", title_sql)
        self.assertIn("title gin_trgm_ops", title_sql)
        self.assertIn("USING gin", alternative_sql)
        self.assertIn("alternative_titles gin_trgm_ops", alternative_sql)

    def test_comic_genre_genre_id_index_is_declared(self):
        index_names = {index.name for index in comic_genre.indexes}
        self.assertIn("ix_comic_genre_genre_id", index_names)


if __name__ == "__main__":
    unittest.main()
