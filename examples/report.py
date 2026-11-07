"""Prints the order total of every customer."""
import argparse
import sqlite3


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-rows", type=int, default=100)
    args = parser.parse_args()
    db = sqlite3.connect("shop.db")
    for row in db.execute("SELECT name, total FROM totals LIMIT ?", (args.max_rows,)):
        print(row)


if __name__ == "__main__":
    main()
