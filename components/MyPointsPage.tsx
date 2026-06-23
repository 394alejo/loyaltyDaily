import React, { useEffect, useState } from 'react';
import { Sparkles } from 'lucide-react';
import { CustomerNavHeader } from './CustomerNavHeader';
import { fetchMyPointsHistory, fetchPointsBalance, PointsLedgerEntry } from '../lib/db/points';
import { isSupabaseConfigured } from '../lib/supabase';
import { useAuth } from './AuthProvider';

const SERVICE_UNAVAILABLE_MESSAGE = 'Service is temporarily unavailable. Please try again later.';

const formatDate = (timestamp: number) =>
  new Date(timestamp).toLocaleDateString('en-US', { month: 'short', day: '2-digit', year: 'numeric' });

export const MyPointsPage: React.FC = () => {
  const { currentUser } = useAuth();
  const [loading, setLoading] = useState(true);
  const [balance, setBalance] = useState(0);
  const [history, setHistory] = useState<PointsLedgerEntry[]>([]);

  useEffect(() => {
    if (!isSupabaseConfigured || !currentUser) {
      setLoading(false);
      return;
    }
    let active = true;
    void (async () => {
      const [historyResult, balanceResult] = await Promise.all([
        fetchMyPointsHistory(),
        fetchPointsBalance(currentUser.id),
      ]);
      if (!active) return;
      setHistory(historyResult);
      setBalance(balanceResult);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [currentUser]);

  if (!isSupabaseConfigured) {
    return (
      <div className="h-screen flex items-center justify-center px-6 text-center text-muted-foreground">
        {SERVICE_UNAVAILABLE_MESSAGE}
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#f5f5f7] px-4 py-10 sm:px-6 sm:py-14">
      <CustomerNavHeader />
      <div className="mx-auto w-full max-w-xl">
        <section className="rounded-[2rem] border border-black/[0.08] bg-white p-6 shadow-[0_24px_64px_-38px_rgba(0,0,0,0.35)] sm:p-8">
          <p className="text-[0.68rem] font-semibold uppercase tracking-[0.26em] text-[#6e6e73]">My Points</p>
          <h1 className="mt-3 text-[clamp(1.7rem,5vw,2.4rem)] font-black leading-[0.96] tracking-[-0.03em] text-[#1d1d1f]">
            {loading ? '...' : balance.toLocaleString()} pts
          </h1>

          {loading ? (
            <div className="flex items-center justify-center py-16">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
            </div>
          ) : history.length === 0 ? (
            <div className="mt-8 flex flex-col items-center justify-center rounded-[1.5rem] border-2 border-dashed border-black/[0.08] bg-[#f5f5f7] py-12 text-center">
              <Sparkles size={32} className="text-[#6e6e73]" />
              <p className="mt-4 text-sm font-medium text-[#1d1d1f]">No points yet</p>
              <p className="mt-1 max-w-xs text-sm text-[#6e6e73]">
                Points are awarded by venues at the end of each month.
              </p>
            </div>
          ) : (
            <div className="mt-6 space-y-3">
              {history.map((entry) => (
                <div
                  key={entry.id}
                  className="flex items-center justify-between gap-4 rounded-[1.25rem] border border-black/[0.06] bg-[#f5f5f7] px-4 py-4"
                >
                  <div>
                    <p className="text-sm font-semibold text-[#1d1d1f]">{entry.description}</p>
                    <p className="mt-0.5 text-xs text-[#6e6e73]">{formatDate(entry.createdAt)}</p>
                  </div>
                  <span
                    className={
                      entry.points > 0
                        ? 'rounded-full border border-emerald-200 bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-700'
                        : 'rounded-full border border-rose-200 bg-rose-50 px-3 py-1 text-xs font-semibold text-rose-700'
                    }
                  >
                    {entry.points > 0 ? `+${entry.points}` : entry.points}
                  </span>
                </div>
              ))}
            </div>
          )}
        </section>
      </div>
    </div>
  );
};
