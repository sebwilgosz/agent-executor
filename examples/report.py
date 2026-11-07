"""Prints the order total of every customer, or one customer's by name."""
import argparse
import sqlite3


def customer(db, name):
    return db.execute("SELECT id, name FROM customers WHERE name = '" + name + "'").fetchone()


def totals(db, customers):
    result = []
    for customer_id, name in customers:
        row = db.execute("SELECT SUM(total) FROM orders WHERE customer_id = ?", (customer_id,)).fetchone()
        result.append((name, row[0]))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--name")
    args = parser.parse_args()
    db = sqlite3.connect("shop.db")
    if args.name:
        print(totals(db, [customer(db, args.name)]))
        return
    customers = db.execute("SELECT id, name FROM customers LIMIT ?", (args.limit,)).fetchall()
    for row in totals(db, customers):
        print(row)


if __name__ == "__main__":
    main()
