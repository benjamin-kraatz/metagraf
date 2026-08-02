import contextlib
import io
import sys
import types
import unittest

# ID discovery does not generate a JWT, but the production module imports
# PyJWT for its real client. Keep this unit test independent of that optional
# local setup dependency.
sys.modules.setdefault("jwt", types.SimpleNamespace())

from Scripts.release.app_store_connect import discover_ids


class FakeClient:
    def get(self, path):
        if path == "/apps/1234567890/ciProduct":
            return {"data": {"id": "product-id"}}
        if path.startswith("/ciProducts/product-id/workflows?"):
            return {
                "data": [
                    {"id": "release-workflow-id", "attributes": {"name": "Mac Release"}},
                    {"id": "ci-workflow-id", "attributes": {"name": "Pull Requests"}},
                ]
            }
        raise AssertionError(f"unexpected API path: {path}")


class DiscoverIDsTests(unittest.TestCase):
    def test_prints_product_and_named_workflow_ids(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            discover_ids(FakeClient(), "1234567890")

        self.assertEqual(
            output.getvalue().splitlines(),
            [
                "APP_STORE_CONNECT_APP_ID=1234567890",
                "XCODE_CLOUD_PRODUCT_ID=product-id",
                "XCODE_CLOUD_WORKFLOW_ID=release-workflow-id  # Mac Release",
                "XCODE_CLOUD_WORKFLOW_ID=ci-workflow-id  # Pull Requests",
            ],
        )


if __name__ == "__main__":
    unittest.main()
