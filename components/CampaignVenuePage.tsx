import React, { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { Button } from './ui/button';
import { useAuth } from './AuthProvider';
import { CustomerNavHeader } from './CustomerNavHeader';
import { fetchVenueCampaign, VenueCampaign } from '../lib/db/campaigns';
import { fetchActiveVenueClaim, insertDiscountClaim } from '../lib/db/transactions';
import { isSupabaseConfigured } from '../lib/supabase';

const SERVICE_UNAVAILABLE_MESSAGE = 'Service is temporarily unavailable. Please try again later.';
const PIN_CHARSET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // excludes 0/O/1/I/L to stay readable at a glance

function generatePin(length = 4): string {
  let pin = '';
  for (let i = 0; i < length; i += 1) {
    pin += PIN_CHARSET[Math.floor(Math.random() * PIN_CHARSET.length)];
  }
  return pin;
}

export const CampaignVenuePage: React.FC = () => {
  const { campaignId } = useParams<{ campaignId: string }>();
  const { currentUser } = useAuth();

  const [loading, setLoading] = useState(true);
  const [venue, setVenue] = useState<VenueCampaign | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [hasPendingClaim, setHasPendingClaim] = useState(false);
  const [error, setError] = useState('');

  const [pin, setPin] = useState('');
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const tick = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(tick);
  }, []);

  useEffect(() => {
    if (!isSupabaseConfigured || !campaignId) {
      setLoading(false);
      return;
    }

    let active = true;
    void (async () => {
      const [venueResult, activeClaim] = await Promise.all([
        fetchVenueCampaign(campaignId),
        fetchActiveVenueClaim(campaignId),
      ]);
      if (!active) return;
      setVenue(venueResult);
      if (activeClaim) {
        setPin(activeClaim.pin);
        setHasPendingClaim(true);
      } else {
        setPin(generatePin());
      }
      setLoading(false);
    })();

    return () => {
      active = false;
    };
  }, [campaignId]);

  if (!isSupabaseConfigured) {
    return (
      <div className="h-screen flex items-center justify-center px-6 text-center text-muted-foreground">
        {SERVICE_UNAVAILABLE_MESSAGE}
      </div>
    );
  }

  if (loading) {
    return (
      <div className="h-screen flex items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
      </div>
    );
  }

  if (!venue || !venue.isEnabled) {
    return (
      <div className="h-screen flex items-center justify-center px-6 text-center text-muted-foreground">
        This venue link is invalid or no longer active.
      </div>
    );
  }

  const handleConfirm = async () => {
    if (!currentUser || !campaignId || hasPendingClaim) return;
    setSubmitting(true);
    setError('');
    const result = await insertDiscountClaim({
      campaignId,
      customerId: currentUser.id,
      pin,
    });
    setSubmitting(false);
    if (!result.ok) {
      setError(result.error ?? 'Unable to submit your claim right now. Please try again.');
      return;
    }
    setHasPendingClaim(true);
  };

  return (
    <div className="min-h-screen bg-[#f5f5f7] px-4 py-10 sm:px-6 sm:py-14">
      <CustomerNavHeader />
      <div className="mx-auto w-full max-w-xl">
        <section className="rounded-[2rem] border border-black/[0.08] bg-white p-6 text-center shadow-[0_24px_64px_-38px_rgba(0,0,0,0.35)] sm:p-8">
          <p className="text-[0.68rem] font-semibold uppercase tracking-[0.26em] text-[#6e6e73]">
            {venue.businessName}
          </p>
          <h1 className="mt-3 text-[clamp(1.9rem,5vw,2.7rem)] font-black leading-[0.96] tracking-[-0.03em] text-[#1d1d1f]">
            {venue.name}
          </h1>
          <p className="mt-3 text-[0.98rem] leading-7 text-[#4f5258]">
            {currentUser?.fullName ?? 'Welcome'} — you get{' '}
            <span className="font-semibold text-[#1d1d1f]">{venue.userDiscountPercent}% off</span> here.
          </p>

          <div className="mt-8 rounded-[1.5rem] border border-black/[0.06] bg-[#f5f5f7] py-8">
            <p className="text-[0.68rem] font-semibold uppercase tracking-[0.26em] text-[#6e6e73]">
              Verification Pin
            </p>
            <p className="mt-2 text-[clamp(3rem,12vw,4.5rem)] font-black tracking-[0.18em] text-[#1d1d1f]">
              {pin}
            </p>
            <p className="mt-3 flex items-center justify-center gap-2 text-[0.8rem] font-medium text-[#6e6e73]">
              <span className="relative flex h-2 w-2">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
                <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-500" />
              </span>
              {now.toLocaleDateString('en-US', { month: 'short', day: '2-digit', year: 'numeric' })} ·{' '}
              {now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
            </p>
          </div>

          {error && (
            <div className="mt-5 rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
              {error}
            </div>
          )}

          {hasPendingClaim ? (
            <p className="mt-6 text-sm font-medium leading-6 text-emerald-700">
              Waiting for cashier to approve. Show this pin to the cashier to redeem your discount.
            </p>
          ) : (
            <Button
              onClick={handleConfirm}
              disabled={submitting}
              className="mt-6 h-12 w-full rounded-xl bg-[#1d1d1f] text-sm font-semibold text-white hover:bg-black/85"
            >
              {submitting ? 'Submitting...' : 'Confirm & Show Cashier'}
            </Button>
          )}
        </section>
      </div>
    </div>
  );
};
