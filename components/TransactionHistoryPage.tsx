import React, { useEffect, useState } from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from './ui/table';
import { History } from 'lucide-react';
import { cn } from '../lib/utils';
import { fetchDiscountClaimHistory, StaffDiscountClaimHistoryEntry } from '../lib/db/transactions';

const formatDateTime = (timestamp: number) => {
  const date = new Date(timestamp);
  return {
    date: date.toLocaleDateString('en-US', { month: 'short', day: '2-digit', year: 'numeric' }),
    time: date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
  };
};

const getStatusBadgeClass = (status: StaffDiscountClaimHistoryEntry['status']) =>
  status === 'confirmed'
    ? 'bg-emerald-100 text-emerald-700 border-emerald-200'
    : 'bg-rose-100 text-rose-700 border-rose-200';

export const TransactionHistoryPage: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [entries, setEntries] = useState<StaffDiscountClaimHistoryEntry[]>([]);

  useEffect(() => {
    let active = true;
    void (async () => {
      const result = await fetchDiscountClaimHistory();
      if (!active) return;
      setEntries(result);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, []);

  return (
    <div className="p-4 md:p-8 space-y-6 animate-fade-in h-full flex flex-col bg-gray-50/50">
      <div>
        <h1 className="text-2xl md:text-3xl font-bold tracking-tight text-foreground">Transaction History</h1>
        <p className="text-muted-foreground">Processed discount claims for your campaigns.</p>
      </div>

      <div className="rounded-xl border bg-white flex-1 overflow-auto shadow-sm">
        <Table>
          <TableHeader>
            <TableRow className="bg-muted/30">
              <TableHead className="w-[180px]">Date & Time</TableHead>
              <TableHead>Customer</TableHead>
              <TableHead>Campaign</TableHead>
              <TableHead>Pin</TableHead>
              <TableHead>Discount</TableHead>
              <TableHead className="text-right">Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={6} className="text-center h-32">
                  <div className="flex justify-center">
                    <div className="h-6 w-6 animate-spin rounded-full border-4 border-primary border-t-transparent" />
                  </div>
                </TableCell>
              </TableRow>
            ) : entries.length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} className="text-center h-32 text-muted-foreground">
                  <div className="flex justify-center mb-2"><History size={24} className="opacity-20" /></div>
                  No processed discount claims yet.
                </TableCell>
              </TableRow>
            ) : (
              entries.map((entry) => {
                const { date, time } = formatDateTime(entry.timestamp);
                return (
                  <TableRow key={entry.id} className="hover:bg-muted/30 transition-colors">
                    <TableCell className="font-mono text-xs text-muted-foreground">
                      <div className="font-medium text-foreground">{date}</div>
                      <div>{time}</div>
                    </TableCell>
                    <TableCell>
                      <div className="font-medium">{entry.customerName ?? 'Customer'}</div>
                    </TableCell>
                    <TableCell>
                      <span className="font-medium text-sm">{entry.campaignName}</span>
                    </TableCell>
                    <TableCell className="font-mono text-sm">{entry.pin}</TableCell>
                    <TableCell className="text-sm">
                      {entry.discountPercent != null ? `${entry.discountPercent}%` : '—'}
                    </TableCell>
                    <TableCell className="text-right">
                      <div
                        className={cn(
                          'inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold border',
                          getStatusBadgeClass(entry.status)
                        )}
                      >
                        {entry.status === 'confirmed' ? 'Confirmed' : 'Rejected'}
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
};
