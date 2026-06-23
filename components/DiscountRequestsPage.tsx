import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Percent, Check, X, Inbox } from 'lucide-react';
import { Button } from './ui/button';
import { Badge } from './ui/badge';
import { fetchPendingDiscountClaims, setDiscountClaimStatus, PendingDiscountClaim } from '../lib/db/transactions';

const POLL_INTERVAL_MS = 4000;

export const DiscountRequestsPage: React.FC = () => {
  const [claims, setClaims] = useState<PendingDiscountClaim[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState('');
  const activeRef = useRef(true);

  const loadClaims = useCallback(async () => {
    const result = await fetchPendingDiscountClaims();
    if (!activeRef.current) return;
    setClaims(result);
    setLoading(false);
  }, []);

  useEffect(() => {
    activeRef.current = true;
    void loadClaims();
    const poll = window.setInterval(() => void loadClaims(), POLL_INTERVAL_MS);
    return () => {
      activeRef.current = false;
      window.clearInterval(poll);
    };
  }, [loadClaims]);

  const handleDecision = async (id: string, status: 'confirmed' | 'rejected') => {
    setBusyId(id);
    setError('');
    const result = await setDiscountClaimStatus(id, status);
    if (!result.ok) {
      setError(result.error ?? 'Unable to update this request right now. Please try again.');
      setBusyId(null);
      return;
    }
    setClaims((prev) => prev.filter((claim) => claim.id !== id));
    setBusyId(null);
  };

  return (
    <div className="p-4 md:p-8 space-y-8 animate-fade-in h-full overflow-y-auto bg-gray-50/50">
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-6 border-b pb-6">
        <div className="flex items-center gap-4">
          <div className="p-3 bg-primary text-primary-foreground rounded-xl shadow-md">
            <Percent size={24} />
          </div>
          <div>
            <h1 className="text-2xl md:text-3xl font-bold tracking-tight text-foreground">Discount Requests</h1>
            <p className="text-muted-foreground">Live queue of customers waiting for discount approval.</p>
          </div>
        </div>
        {claims.length > 0 && (
          <Badge variant="secondary" className="text-sm">
            {claims.length} pending
          </Badge>
        )}
      </header>

      {error && (
        <div className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
          {error}
        </div>
      )}

      {loading ? (
        <div className="flex items-center justify-center h-64">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
        </div>
      ) : claims.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-[400px] border-2 border-dashed border-gray-200 rounded-[2rem] bg-white/50">
          <div className="bg-white p-6 rounded-full shadow-sm mb-6">
            <Inbox size={40} className="text-muted-foreground" />
          </div>
          <h3 className="text-2xl font-bold text-foreground">No pending requests</h3>
          <p className="text-muted-foreground max-w-sm text-center mt-2">
            New discount claims from customers will show up here automatically.
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-[repeat(auto-fill,minmax(320px,1fr))] gap-6">
          {claims.map((claim) => (
            <div
              key={claim.id}
              className="rounded-2xl border border-black/[0.06] bg-white p-5 shadow-sm flex flex-col gap-4"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                    {claim.campaignName}
                  </p>
                  <p className="mt-1 text-lg font-bold text-foreground">
                    {claim.customerName ?? 'Customer'}
                  </p>
                </div>
                <Badge variant="outline" className="shrink-0">
                  {claim.discountPercent}% off
                </Badge>
              </div>

              <div className="rounded-xl bg-gray-50 py-3 text-center">
                <p className="text-[0.65rem] font-semibold uppercase tracking-[0.2em] text-muted-foreground">
                  Pin
                </p>
                <p className="mt-1 text-2xl font-black tracking-[0.18em] text-foreground">{claim.pin}</p>
              </div>

              <div className="flex gap-2">
                <Button
                  variant="outline"
                  className="flex-1 gap-2 border-rose-200 text-rose-700 hover:bg-rose-50"
                  disabled={busyId === claim.id}
                  onClick={() => handleDecision(claim.id, 'rejected')}
                >
                  <X size={16} /> Reject
                </Button>
                <Button
                  className="flex-1 gap-2"
                  disabled={busyId === claim.id}
                  onClick={() => handleDecision(claim.id, 'confirmed')}
                >
                  <Check size={16} /> Approve
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
