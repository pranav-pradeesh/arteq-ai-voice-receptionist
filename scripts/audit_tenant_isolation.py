#!/usr/bin/env python3
"""Static tenant-isolation audit.

Scans every .py file for SQL statements touching tenant-scoped tables and
flags those with no hospital_id / tenant_slug / hospital-scoped join in the
same statement. Heuristic — findings need human review, but a clean run means
no obvious cross-tenant query slipped in.

Usage: python3 scripts/audit_tenant_isolation.py [--all]
  default: print only suspects; --all also lists clean statements.
"""
import pathlib
import re
import sys

TENANT_TABLES = {
    "appointments", "call_logs", "patients", "doctors", "departments",
    "doctor_patients", "callbacks", "outbound_call_queue", "call_handoffs",
    "campaigns", "campaign_recipients", "schedules", "emergency_contacts",
    "faqs", "billing_info", "bookings", "whatsapp_messages",
    "appointment_events", "missed_questions",
}
SCOPE_MARKERS = ("hospital_id", "tenant_slug", "hospitals h", "call_id", "id = $", "id=$", "WHERE id")
SQL_RE = re.compile(r'"""(.*?)"""|\'\'\'(.*?)\'\'\'|"([^"\n]*)"', re.DOTALL)
VERB_RE = re.compile(r"\b(SELECT|UPDATE|DELETE\s+FROM|INSERT\s+INTO)\b", re.IGNORECASE)


def table_hits(sql: str):
    low = re.sub(r"\s+", " ", sql.lower())
    return {t for t in TENANT_TABLES if re.search(rf"\b(from|into|update|join)\s+{t}\b", low)}


def main() -> int:
    show_all = "--all" in sys.argv
    root = pathlib.Path(__file__).resolve().parent.parent
    suspects = clean = 0
    for py in sorted(root.rglob("*.py")):
        rel = py.relative_to(root)
        if any(part in ("__pycache__", "node_modules", ".git", "scripts") for part in rel.parts):
            continue
        text = py.read_text(encoding="utf-8", errors="replace")
        for m in SQL_RE.finditer(text):
            sql = next((g for g in m.groups() if g), "")
            if not sql or not VERB_RE.search(sql):
                continue
            tables = table_hits(sql)
            if not tables:
                continue
            line = text[: m.start()].count("\n") + 1
            scoped = any(mark.lower() in sql.lower() for mark in SCOPE_MARKERS)
            if scoped:
                clean += 1
                if show_all:
                    print(f"  ok    {rel}:{line}  {sorted(tables)}")
            else:
                suspects += 1
                head = re.sub(r"\s+", " ", sql.strip())[:110]
                print(f"  CHECK {rel}:{line}  {sorted(tables)}  :: {head}")
    print(f"\n{suspects} suspect statement(s), {clean} scoped statement(s).")
    return 1 if suspects else 0


if __name__ == "__main__":
    raise SystemExit(main())
