from urllib.request import Request, urlopen

request = Request("https://example.com", data=b"body",
                  headers={"Accept": "text/html"}, method="POST")
assert request.get_full_url() == "https://example.com"
assert request.get_method() == "POST"
assert request.data == b"body"
request = Request("https://example.com", headers={"Accept": "text/html"})
assert request.get_method() == "GET"
assert request.has_header("Accept")
request.add_header("X-NPython-Test", "1")
assert request.get_header("X-NPython-Test") == "1"
assert urlopen is not None
