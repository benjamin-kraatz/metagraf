import io
import json
import os
import unittest
import urllib.error
from unittest.mock import patch

from Scripts.release.app_store_connect import AppStoreConnect, ArtifactNotReady, find_notarized_artifact


class Response:
    def __init__(self, payload):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self):
        return json.dumps(self.payload).encode()


class AppStoreConnectTests(unittest.TestCase):
    def test_token_allows_clock_skew_and_stays_below_twenty_minutes(self):
        environment = {
            "ASC_PRIVATE_KEY": "private-key",
            "ASC_ISSUER_ID": "issuer",
            "ASC_KEY_ID": "key-id",
        }
        with patch.dict(os.environ, environment, clear=False), patch("time.time", return_value=1_000), patch(
            "jwt.encode", return_value="signed-token"
        ) as encode:
            authorization = AppStoreConnect().authorization()

        claims = encode.call_args.args[0]
        self.assertEqual(authorization, "Bearer signed-token")
        self.assertEqual(claims["iat"], 940)
        self.assertEqual(claims["exp"], 1_600)
        self.assertLess(claims["exp"] - claims["iat"], 20 * 60)

    def test_get_retries_unauthorized_with_new_authorization(self):
        unauthorized = urllib.error.HTTPError(
            "https://example.test",
            401,
            "Unauthorized",
            {},
            io.BytesIO(b'{"errors":[]}'),
        )
        client = AppStoreConnect.__new__(AppStoreConnect)
        with patch.object(client, "authorization", side_effect=("Bearer first", "Bearer second")) as authorization, patch(
            "urllib.request.urlopen", side_effect=(unauthorized, Response({"data": "ok"}))
        ) as urlopen, patch("time.sleep") as sleep:
            result = client.get("/ciBuildRuns/build-id")

        self.assertEqual(result, {"data": "ok"})
        self.assertEqual(authorization.call_count, 2)
        self.assertEqual(urlopen.call_count, 2)
        sleep.assert_called_once_with(1)

    def test_notarized_artifact_does_not_require_notarize_action_type(self):
        actions = [
            {
                "id": "archive-action",
                "attributes": {"name": "Archive", "actionType": "ARCHIVE", "completionStatus": "SUCCEEDED"},
            },
            {
                "id": "test-action",
                "attributes": {"name": "Test", "actionType": "TEST", "completionStatus": "SUCCEEDED"},
            },
        ]
        artifact = {
            "id": "artifact-id",
            "attributes": {"fileType": "STAPLED_NOTARIZED_ARCHIVE"},
        }
        client = AppStoreConnect.__new__(AppStoreConnect)
        client.get = lambda path: {
            "/ciBuildRuns/build-id/actions?limit=200": {"data": actions},
            "/ciBuildActions/archive-action/artifacts?limit=200": {"data": [artifact]},
        }.get(path, {"data": []})

        found, found_actions = find_notarized_artifact(client, "build-id")

        self.assertEqual(found, artifact)
        self.assertEqual(found_actions, actions)

    def test_missing_notarized_artifact_is_retryable(self):
        action = {
            "id": "archive-action",
            "attributes": {"name": "Archive", "actionType": "ARCHIVE", "completionStatus": "SUCCEEDED"},
        }
        client = AppStoreConnect.__new__(AppStoreConnect)
        client.get = lambda path: {"data": [action]} if "/actions?" in path else {"data": []}

        with self.assertRaises(ArtifactNotReady):
            find_notarized_artifact(client, "build-id")


if __name__ == "__main__":
    unittest.main()
