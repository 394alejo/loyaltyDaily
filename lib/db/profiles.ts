import { supabase } from '../supabase';
import type { User, UserRole } from '../../types';

export const profileToUser = (row: Record<string, unknown>): User => ({
  id: row.id as string,
  businessName: row.business_name as string,
  fullName: (row.full_name as string | null) ?? undefined,
  email: row.email as string,
  slug: row.slug as string | undefined,
  role: row.role as UserRole,
  ownerId: row.owner_id as string | undefined,
  status: row.status as 'unverified' | 'verified',
  access: row.access as 'active' | 'disabled',
  tier: (row.tier as 'free' | 'pro') ?? 'free',
  tierExpiresAt: row.tier_expires_at as string | undefined,
  createdAt: row.created_at as string,
});

export type ProfileFetchResult = {
  user: User | null;
  error: string | null;
  code?: string | null;
};

export async function fetchProfileDetailed(userId: string): Promise<ProfileFetchResult> {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .maybeSingle();

  if (error) {
    const errorCode = typeof (error as { code?: string }).code === 'string'
      ? (error as { code: string }).code
      : null;
    return { user: null, error: error.message, code: errorCode };
  }
  if (!data) return { user: null, error: null };
  return { user: profileToUser(data), error: null, code: null };
}

export async function fetchProfile(userId: string): Promise<User | null> {
  const result = await fetchProfileDetailed(userId);
  return result.user;
}

export async function fetchProfileBySlug(slug: string): Promise<User | null> {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('slug', slug)
    .eq('role', 'owner')
    .single();
  if (error || !data) return null;
  return profileToUser(data);
}

export async function fetchStaffAccounts(ownerId: string): Promise<User[]> {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('owner_id', ownerId)
    .eq('role', 'staff');
  if (error || !data) return [];
  return data.map(profileToUser);
}

export async function updateProfile(
  userId: string,
  updates: { business_name?: string; email?: string; slug?: string; status?: string; access?: string; tier?: string; tier_expires_at?: string | null }
): Promise<{ ok: boolean; error?: string }> {
  const { error } = await supabase
    .from('profiles')
    .update(updates)
    .eq('id', userId);
  if (error) return { ok: false, error: 'Unable to update this profile right now. Please try again.' };
  return { ok: true };
}

export async function isSlugAvailable(slug: string): Promise<boolean> {
  const { data, error } = await supabase
    .rpc('is_slug_available', { slug_input: slug });
  if (error) return false;
  return data === true;
}
