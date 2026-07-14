import unittest

from sqlalchemy import select
from sqlalchemy.dialects import postgresql

from app.api.v1.sources import (
    _apply_source_comic_filters,
    _apply_source_comic_sort,
    _latest_feed_order,
    _popular_feed_order,
    _top_ranking_order,
)
from app.models import Comic


def compile_sql(statement) -> str:
    return str(statement.compile(dialect=postgresql.dialect()))


class SourceFeedSqlTests(unittest.TestCase):
    def test_latest_feed_order_matches_source_scoped_index(self):
        sql = compile_sql(
            select(Comic.id)
            .where(Comic.source_name == "komikcast")
            .order_by(*_latest_feed_order())
            .limit(20)
        )
        self.assertIn(
            "ORDER BY comics.latest_feed_batch_at DESC NULLS LAST, "
            "comics.latest_feed_page ASC NULLS LAST, "
            "comics.latest_feed_position ASC NULLS LAST, "
            "comics.updated_at DESC, comics.id ASC",
            sql,
        )
        self.assertNotIn("chapters", sql)

    def test_popular_feed_order_matches_source_scoped_index(self):
        sql = compile_sql(
            select(Comic.id)
            .where(Comic.source_name == "komikcast")
            .order_by(*_popular_feed_order())
            .limit(20)
        )
        self.assertIn(
            "ORDER BY comics.popular_feed_batch_at DESC NULLS LAST, "
            "comics.popular_feed_page ASC NULLS LAST, "
            "comics.popular_feed_position ASC NULLS LAST, "
            "comics.rating DESC NULLS LAST, "
            "comics.total_view DESC NULLS LAST, comics.updated_at DESC, "
            "comics.id ASC",
            sql,
        )
        self.assertNotIn("chapters", sql)

    def test_model_declares_source_scoped_feed_indexes(self):
        index_names = {index.name for index in Comic.__table__.indexes}
        self.assertIn("ix_comics_source_latest_feed_order", index_names)
        self.assertIn("ix_comics_source_popular_feed_order", index_names)
        self.assertIn("ix_comics_source_top_view_order", index_names)

    def test_top_ranking_order_matches_source_scoped_index(self):
        sql = compile_sql(
            select(Comic.id)
            .where(Comic.source_name == "komikcast")
            .order_by(*_top_ranking_order())
            .limit(10)
        )
        self.assertIn(
            "ORDER BY comics.total_view DESC NULLS LAST, "
            "comics.rating DESC NULLS LAST, comics.title ASC, comics.id ASC",
            sql,
        )
        self.assertNotIn("chapters", sql)

    def test_total_view_sort_orders_catalog_by_highest_views(self):
        sql = compile_sql(
            _apply_source_comic_sort(
                select(Comic.id).where(Comic.source_name == "komikcast"),
                "total_view",
            ).limit(20)
        )

        self.assertIn(
            "ORDER BY comics.total_view DESC NULLS LAST, "
            "comics.rating DESC NULLS LAST, comics.title ASC, comics.id ASC",
            sql,
        )
        self.assertNotIn("chapters", sql)

    def test_source_comic_filters_apply_type_status_and_genre(self):
        sql = compile_sql(
            _apply_source_comic_filters(
                select(Comic.id).where(Comic.source_name == "komikcast"),
                type="Manhwa",
                status="Ongoing",
                genre="Action",
            ).limit(20)
        )

        self.assertIn("lower(comics.type) IN ", sql)
        self.assertIn("lower(comics.status) IN ", sql)
        self.assertIn("EXISTS", sql)
        self.assertIn("genres", sql)
        self.assertNotIn("chapters", sql)


if __name__ == "__main__":
    unittest.main()
