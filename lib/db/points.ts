import { supabase } from '../supabase';

export interface PointsLedgerEntry {
  id: string;
  points: number;
  description: string;
  createdAt: number;
}

export async function fetchMyPointsHistory(): Promise<PointsLedgerEntry[]> {
  const { data, error } = await supabase
    .from('points_ledger')
    .select('id, points, description, created_at')
    .order('created_at', { ascending: false });
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((row) => ({
    id: row.id as string,
    points: Number(row.points),
    description: row.description as string,
    createdAt: new Date(row.created_at as string).getTime(),
  }));
}

export async function fetchPointsBalance(customerId: string): Promise<number> {
  const { data, error } = await supabase.rpc('get_customer_points_balance', {
    customer_id_input: customerId,
  });
  if (error || data == null) return 0;
  return Number(data);
}

export interface CustomerSearchResult {
  id: string;
  fullName: string | null;
  email: string;
}

export async function fetchAllCustomers(): Promise<CustomerSearchResult[]> {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, full_name, email')
    .eq('role', 'customer')
    .order('full_name', { ascending: true });
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((row) => ({
    id: row.id as string,
    fullName: (row.full_name as string | null) ?? null,
    email: row.email as string,
  }));
}

export async function awardPoints(payload: {
  customerId: string;
  points: number;
  description: string;
}): Promise<{ ok: boolean; error?: string }> {
  const { error } = await supabase.from('points_ledger').insert({
    customer_id: payload.customerId,
    points: payload.points,
    description: payload.description,
  });
  if (error) return { ok: false, error: 'Unable to award points right now. Please try again.' };
  return { ok: true };
}
