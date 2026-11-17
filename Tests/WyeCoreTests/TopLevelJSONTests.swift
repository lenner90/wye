import XCTest
@testable import WyeCore

final class TopLevelJSONTests: XCTestCase {
    let sample = """
    {
      "numStartups": 0.1,
      "tricky": "a \\" } ] , { [ b",
      "oauthAccount": {
        "emailAddress": "p@example.com",
        "nested": {"k": [1, 2, {"x": "}"}]}
      },
      "userID": "abc"
    }
    """

    private func data(_ s: String) -> Data { Data(s.utf8) }
    private func string(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    func testReadsRawValueOfKey() throws {
        let value = try TopLevelJSON.value(forKey: "userID", in: data(sample))
        XCTAssertEqual(value.map(string), "\"abc\"")
    }

    func testReadsObjectValueDespiteBracesInsideStrings() throws {
        let value = try XCTUnwrap(TopLevelJSON.value(forKey: "oauthAccount", in: data(sample)))
        let parsed = try JSONSerialization.jsonObject(with: value) as? [String: Any]
        XCTAssertEqual(parsed?["emailAddress"] as? String, "p@example.com")
    }

    func testMissingKeyReadsAsNil() throws {
        XCTAssertNil(try TopLevelJSON.value(forKey: "nope", in: data(sample)))
    }

    func testReplacingValueLeavesEveryOtherByteUntouched() throws {
        let out = string(try TopLevelJSON.setting(
            key: "oauthAccount", rawValue: data("{\"emailAddress\":\"c@corp.com\"}"), in: data(sample)))
        let expected = """
        {
          "numStartups": 0.1,
          "tricky": "a \\" } ] , { [ b",
          "oauthAccount": {"emailAddress":"c@corp.com"},
          "userID": "abc"
        }
        """
        XCTAssertEqual(out, expected)
    }

    func testSettingMissingKeyAddsItAndKeepsExistingText() throws {
        let original = "{\n  \"a\": 1\n}"
        let out = string(try TopLevelJSON.setting(key: "b", rawValue: data("[2]"), in: data(original)))
        XCTAssertTrue(out.hasPrefix("{\n  \"a\": 1"))
        let parsed = try JSONSerialization.jsonObject(with: data(out)) as? [String: Any]
        XCTAssertEqual(parsed?["a"] as? Int, 1)
        XCTAssertEqual(parsed?["b"] as? [Int], [2])
    }

    func testSettingKeyOnEmptyObject() throws {
        let out = try TopLevelJSON.setting(key: "b", rawValue: data("true"), in: data("{}"))
        let parsed = try JSONSerialization.jsonObject(with: out) as? [String: Any]
        XCTAssertEqual(parsed?["b"] as? Bool, true)
    }

    func testRemovingMiddleKey() throws {
        let out = string(try TopLevelJSON.removing(key: "oauthAccount", from: data(sample)))
        let expected = """
        {
          "numStartups": 0.1,
          "tricky": "a \\" } ] , { [ b",
          "userID": "abc"
        }
        """
        XCTAssertEqual(out, expected)
    }

    func testRemovingLastKeyDropsThePrecedingComma() throws {
        let out = string(try TopLevelJSON.removing(key: "b", from: data("{\"a\": 1, \"b\": 2}")))
        XCTAssertEqual(out, "{\"a\": 1}")
    }

    func testRemovingOnlyKey() throws {
        let out = string(try TopLevelJSON.removing(key: "a", from: data("{\"a\": 1}")))
        XCTAssertEqual(out, "{}")
    }

    func testRemovingMissingKeyChangesNothing() throws {
        XCTAssertEqual(try TopLevelJSON.removing(key: "zzz", from: data(sample)), data(sample))
    }

    func testMalformedDocumentThrows() {
        XCTAssertThrowsError(try TopLevelJSON.value(forKey: "a", in: data("{\"a\": [1, 2")))
        XCTAssertThrowsError(try TopLevelJSON.value(forKey: "a", in: data("[1]")))
    }

    func testRefusesToWriteInvalidRawValue() {
        XCTAssertThrowsError(
            try TopLevelJSON.setting(key: "a", rawValue: data("{oops"), in: data("{}")))
    }
}
