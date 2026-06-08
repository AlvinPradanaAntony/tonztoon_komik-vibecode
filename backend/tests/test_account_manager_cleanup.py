import unittest
from unittest.mock import AsyncMock, patch
from uuid import uuid4

from sqlalchemy.dialects import postgresql

from app.schemas.account_manager import AccountRelationCounts
from app.services.account_manager_service import delete_account_clean


def compile_sql(statement) -> str:
    return str(statement.compile(dialect=postgresql.dialect()))


class FakeDb:
    def __init__(self):
        self.statements = []
        self.commit_count = 0
        self.rollback_count = 0

    async def execute(self, statement):
        self.statements.append(statement)

    async def commit(self):
        self.commit_count += 1

    async def rollback(self):
        self.rollback_count += 1


class AccountManagerCleanupTests(unittest.IsolatedAsyncioTestCase):
    async def test_delete_account_clean_removes_bookmark_links_explicitly(self):
        user_id = uuid4()
        db = FakeDb()
        counts = AccountRelationCounts(
            user_bookmarks=1,
            user_bookmark_links=2,
            user_completed_chapters=3,
            user_reading_stats=1,
        )

        with (
            patch(
                "app.services.account_manager_service.get_relation_counts",
                AsyncMock(return_value=counts),
            ),
            patch(
                "app.services.account_manager_service._request_admin",
                AsyncMock(return_value={}),
            ),
        ):
            response = await delete_account_clean(db, user_id)

        sql = [compile_sql(statement) for statement in db.statements]
        bookmark_link_delete_index = next(
            index
            for index, statement_sql in enumerate(sql)
            if "DELETE FROM user_bookmark_links" in statement_sql
        )
        bookmark_delete_index = next(
            index
            for index, statement_sql in enumerate(sql)
            if "DELETE FROM user_bookmarks" in statement_sql
        )

        self.assertLess(bookmark_link_delete_index, bookmark_delete_index)
        self.assertEqual(response.relation_counts.user_bookmark_links, 2)
        self.assertEqual(response.relation_total, 7)
        self.assertEqual(db.commit_count, 1)
        self.assertEqual(db.rollback_count, 0)


if __name__ == "__main__":
    unittest.main()
