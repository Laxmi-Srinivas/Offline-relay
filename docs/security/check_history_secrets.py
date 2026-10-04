"""Read-only, limited secret-pattern triage. Prints locations, never matched values.

Not a complete credential scanner: unknown formats, binary/large blobs, unreferenced
objects, ignored files, remote-only history and encoded secrets remain unchecked.
"""
import re
import subprocess


def git(*args, input_bytes=None):
    return subprocess.run(
        ["git", "--no-optional-locks", *args], input=input_bytes,
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout


patterns = {
    "private-key-header": rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
    "aws-access-id": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "github-token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,})\b",
    "google-api-key": rb"\bAIza[A-Za-z0-9_-]{35}\b",
    "literal-secret-assignment": rb"(?i)(?:api[_-]?key|client[_-]?secret|password|access[_-]?token)\s*[:=]\s*['\"][^'\"\r\n]{12,}['\"]",
}
objects = {}
for line in git("rev-list", "--objects", "--all").decode("utf-8").splitlines():
    oid, _, path = line.partition(" ")
    objects.setdefault(oid, path)
metadata = git("cat-file", "--batch-check", input_bytes=("\n".join(objects) + "\n").encode())
counts = {"text_blobs": 0, "binary_skipped": 0, "large_skipped": 0, "candidates": 0}
for row in metadata.decode().splitlines():
    oid, kind, size = row.split()
    if kind != "blob":
        continue
    if int(size) > 2 * 1024 * 1024:
        counts["large_skipped"] += 1
        continue
    content = git("cat-file", "blob", oid)
    if b"\0" in content:
        counts["binary_skipped"] += 1
        continue
    counts["text_blobs"] += 1
    for label, pattern in patterns.items():
        for match in re.finditer(pattern, content):
            counts["candidates"] += 1
            line_number = content[:match.start()].count(b"\n") + 1
            print(f"CANDIDATE {label}: {objects[oid]}:{line_number} blob={oid}")
print(counts)
