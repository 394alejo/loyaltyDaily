import { supabase } from '../supabase';

export interface PendingDiscountClaim {
  id: string;
  campaignId: string;
  campaignName: string;
  customerName: string | null;
  pin: string;
  discountPercent: number;
  timestamp: number;
}

export async function fetchPendingDiscountClaims(): Promise<PendingDiscountClaim[]> {
  const { data, error } = await supabase.rpc('get_pending_discount_claims');
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((row) => ({
    id: row.id as string,
    campaignId: row.campaignId as string,
    campaignName: row.campaignName as string,
    customerName: (row.customerName as string | null) ?? null,
    pin: row.pin as string,
    discountPercent: Number(row.discountPercent),
    timestamp: Number(row.timestamp),
  }));
}

export async function setDiscountClaimStatus(
  transactionId: string,
  status: 'confirmed' | 'rejected'
): Promise<{ ok: boolean; error?: string }> {
  const { data, error } = await supabase.rpc('set_discount_claim_status', {
    transaction_id_input: transactionId,
    new_status: status,
  });
  const failureMessage = status === 'confirmed'
    ? 'Unable to approve this request right now. Please try again.'
    : 'Unable to reject this request right now. Please try again.';
  if (error) return { ok: false, error: failureMessage };
  if (typeof data === 'object' && data && 'success' in data && (data as { success?: boolean }).success === false) {
    return { ok: false, error: failureMessage };
  }
  return { ok: true };
}

export interface DiscountClaimHistoryEntry {
  id: string;
  venueName: string;
  campaignName: string;
  discountPercent: number | null;
  status: 'confirmed' | 'rejected';
  timestamp: number;
}

export async function fetchMyDiscountClaims(): Promise<DiscountClaimHistoryEntry[]> {
  const { data, error } = await supabase.rpc('get_my_discount_claims');
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((row) => ({
    id: row.id as string,
    venueName: row.venueName as string,
    campaignName: row.campaignName as string,
    discountPercent: row.discountPercent == null ? null : Number(row.discountPercent),
    status: row.status as 'confirmed' | 'rejected',
    timestamp: Number(row.timestamp),
  }));
}

export interface StaffDiscountClaimHistoryEntry {
  id: string;
  campaignName: string;
  customerName: string | null;
  pin: string;
  discountPercent: number | null;
  status: 'confirmed' | 'rejected';
  timestamp: number;
}

export async function fetchDiscountClaimHistory(): Promise<StaffDiscountClaimHistoryEntry[]> {
  const { data, error } = await supabase.rpc('get_discount_claim_history');
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((row) => ({
    id: row.id as string,
    campaignName: row.campaignName as string,
    customerName: (row.customerName as string | null) ?? null,
    pin: row.pin as string,
    discountPercent: row.discountPercent == null ? null : Number(row.discountPercent),
    status: row.status as 'confirmed' | 'rejected',
    timestamp: Number(row.timestamp),
  }));
}

export interface ActiveVenueClaim {
  id: string;
  pin: string;
}

export async function fetchActiveVenueClaim(campaignId: string): Promise<ActiveVenueClaim | null> {
  const { data, error } = await supabase.rpc('get_active_venue_claim', { campaign_id_input: campaignId });
  if (error || !data) return null;
  return { id: data.id as string, pin: data.pin as string };
}

export async function insertDiscountClaim(payload: {
  campaignId: string;
  customerId: string;
  pin: string;
}): Promise<{ ok: boolean; error?: string }> {
  const now = new Date();
  const { error } = await supabase.from('transactions').insert({
    campaign_id: payload.campaignId,
    customer_id: payload.customerId,
    pin: payload.pin,
    status: 'pending',
    type: 'discount_claim',
    date: now.toLocaleDateString('en-US', { month: 'short', day: '2-digit', year: 'numeric' }),
    timestamp: now.getTime(),
    title: 'Discount Claim Requested',
  });
  if (error) return { ok: false, error: 'Unable to submit your claim right now. Please try again.' };
  return { ok: true };
}
