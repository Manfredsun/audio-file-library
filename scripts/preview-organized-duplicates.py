#!/usr/bin/env python3
"""Read-only preview of previously indexed generated hard links. Never repairs data."""
import argparse
import json
import sqlite3
from pathlib import Path


def preview(path):
    connection = sqlite3.connect(Path(path).resolve().as_uri() + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute("PRAGMA query_only = ON")
        rows = connection.execute("""
            SELECT generated.id AS generated_id, generated.library_id,
                   generated.relative_path, generated.display_name,
                   generated.category_source,
                   (SELECT MIN(original.id) FROM sounds original
                     WHERE original.library_id = generated.library_id
                       AND original.file_identifier = generated.file_identifier
                       AND original.id <> generated.id
                       AND substr(original.relative_path, 1, 11) <> '_Organized/') AS original_id
              FROM sounds generated
             WHERE substr(generated.relative_path, 1, 11) = '_Organized/'
             ORDER BY generated.library_id, generated.id
            """).fetchall()
        return [dict(row) for row in rows]
    finally:
        connection.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    args = parser.parse_args()
    print(json.dumps({"read_only": True, "candidates": preview(args.database)}, ensure_ascii=False, indent=2))
