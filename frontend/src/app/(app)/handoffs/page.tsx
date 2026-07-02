"use client";
import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import type { Handoff } from "@/lib/types";
import { fmtDateTime } from "@/lib/utils";
import { PageHeader, Badge, Spinner } from "@/components/ui";
import { DataTable, ColumnDef } from "@/components/data-table";
import { RequireHospital } from "@/components/require-hospital";

function HandoffsInner({ hospitalId }: { hospitalId: string }) {
  const { data = [], isLoading } = useQuery({
    queryKey: ["handoffs", hospitalId],
    queryFn: () => api.listHandoffs(hospitalId),
    refetchInterval: 30_000, // reception watches this — keep it fresh
  });

  const columns: ColumnDef<Handoff, unknown>[] = [
    {
      header: "When",
      accessorKey: "created_at",
      cell: ({ row }) => fmtDateTime(row.original.created_at),
    },
    {
      header: "Reason",
      accessorKey: "reason",
      cell: ({ row }) => <Badge tone="yellow">{row.original.reason}</Badge>,
    },
    { header: "Transferred To", accessorKey: "to_phone" },
    {
      header: "Connected",
      accessorKey: "succeeded",
      cell: ({ row }) =>
        row.original.succeeded ? <Badge tone="green">yes</Badge> : <Badge tone="red">no</Badge>,
    },
    {
      header: "Conversation (last turns)",
      accessorKey: "transcript_tail",
      cell: ({ row }) =>
        row.original.transcript_tail ? (
          <details>
            <summary className="cursor-pointer text-sm text-blue-600">show</summary>
            <pre className="mt-2 max-w-xl whitespace-pre-wrap text-xs text-gray-700">
              {row.original.transcript_tail}
            </pre>
          </details>
        ) : (
          <span className="text-gray-400">—</span>
        ),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Human Handoffs"
        subtitle="Calls the AI transferred to reception — with the conversation context at the moment of transfer."
      />
      {isLoading ? <Spinner /> : <DataTable columns={columns} data={data} />}
    </div>
  );
}

export default function HandoffsPage() {
  return <RequireHospital>{(hid) => <HandoffsInner hospitalId={hid} />}</RequireHospital>;
}
