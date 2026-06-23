import React, { useEffect, useState } from 'react';
import { Inbox } from 'lucide-react';
import { CustomerNavHeader } from './CustomerNavHeader';
import { fetchMyDiscountClaims, DiscountClaimHistoryEntry } from '../lib/db/transactions';
import { isSupabaseConfigured } from '../lib/supabase';

const SERVICE_UNAVAILABLE_MESSAGE = 'Service is temporarily unavailable. Please try again later.';

const formatDateTime = (timestamp: number) => {
  const date = new Date(timestamp);
  return {
    date: date.toLocaleDateString('en-US', { month: 'short', day: '2-digit', year: 'numeric' }),
    time: date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
  };
};

const StatusBadge: React.FC<{ status: DiscountClaimHistoryEntry['status'] }> = ({ status }) => {
  const isConfirmed = status === 'confirmed';
  return (
    <span
      className={
        isConfirmed
          ? 'rounded-full border border-emerald-200 bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-700'
          : 'rounded-full border border-rose-200 bg-rose-50 px-3 py-1 text-xs font-semibold text-rose-700'
      }
    >
      {isConfirmed ? 'Confirmed' : 'Rejected'}
    </span>
  );
};

export const MyVisitsPage: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [visits, setVisits] = useState<DiscountClaimHistoryEntry[]>([]);

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setLoading(false);
      return;
    }
    let active = true;
    void (async () => {
      const result = await fetchMyDiscountClaims();
      if (!active) return;
      setVisits(result);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, []);

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
          <p className="text-[0.68rem] font-semibold uppercase tracking-[0.26em] text-[#6e6e73]">My Visits</p>
          <h1 className="mt-3 text-[clamp(1.7rem,5vw,2.4rem)] font-black leading-[0.96] tracking-[-0.03em] text-[#1d1d1f]">
            Your discount history
          </h1>

          {loading ? (
            <div className="flex items-center justify-center py-16">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
            </div>
          ) : visits.length === 0 ? (
            <div className="mt-8 flex flex-col items-center justify-center rounded-[1.5rem] border-2 border-dashed border-black/[0.08] bg-[#f5f5f7] py-12 text-center">
              <Inbox size={32} className="text-[#6e6e73]" />
              <p className="mt-4 text-sm font-medium text-[#1d1d1f]">No visits yet</p>
              <p className="mt-1 max-w-xs text-sm text-[#6e6e73]">
                Once you claim a discount at a venue, it will show up here.
              </p>
            </div>
          ) : (
            <div className="mt-6 space-y-3">
              {visits.map((visit) => {
                const { date, time } = formatDateTime(visit.timestamp);
                return (
                  <div
                    key={visit.id}
                    className="flex items-center justify-between gap-4 rounded-[1.25rem] border border-black/[0.06] bg-[#f5f5f7] px-4 py-4"
                  >
                    <div>
                      <p className="text-sm font-semibold text-[#1d1d1f]">{visit.venueName}</p>
                      <p className="mt-0.5 text-xs text-[#6e6e73]">
                        {date} · {time}
                        {visit.discountPercent != null ? ` · ${visit.discountPercent}% off` : ''}
                      </p>
                    </div>
                    <StatusBadge status={visit.status} />
                  </div>
                );
              })}
            </div>
          )}
        </section>
      </div>
    </div>
  );
};
