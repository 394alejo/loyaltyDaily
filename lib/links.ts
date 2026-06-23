import type { UserRole } from "../types";

export const getDefaultRouteForRole = (role: UserRole | null | undefined): string => {
  if (role === "customer") return "/customer/visits";
  if (role === "admin") return "/admin/award-points";
  if (role === "owner" || role === "staff") return "/discount-requests";
  return "/login";
};

export const buildPublicCardUrl = (slug: string, uniqueId: string) => {
  if (!slug) return "";
  if (typeof window === "undefined") return `/${slug}/${uniqueId}`;
  return `${window.location.origin}/${slug}/${uniqueId}`;
};

export const buildCampaignSignupUrl = (slug: string, campaignId: string) => {
  if (!slug || !campaignId) return "";
  const path = `/${slug}/join/${encodeURIComponent(campaignId)}`;
  if (typeof window === "undefined") return path;
  return `${window.location.origin}${path}`;
};

export const buildVenueDiscountUrl = (campaignId: string) => {
  if (!campaignId) return "";
  const path = `/venue/${encodeURIComponent(campaignId)}`;
  if (typeof window === "undefined") return path;
  return `${window.location.origin}${path}`;
};

export const buildStaffPortalUrl = (slug: string, orgId: string, kioskUniqueId?: string) => {
  if (!slug || !orgId) return "";
  const params = new URLSearchParams({ id: orgId });
  if (kioskUniqueId) {
    params.set("kiosk", kioskUniqueId);
  }
  const path = `/${slug}/staff?${params.toString()}`;
  if (typeof window === "undefined") return path;
  return `${window.location.origin}${path}`;
};

export const buildStaffScanEntryUrl = (slug: string, uniqueId: string) => {
  if (!slug || !uniqueId) return "";
  const path = `/${slug}/scan/${encodeURIComponent(uniqueId)}`;
  if (typeof window === "undefined") return path;
  return `${window.location.origin}${path}`;
};

export const buildIssuedCardsKioskUrl = (uniqueId: string) => {
  if (!uniqueId) return "/issued-cards";
  return `/issued-cards?kiosk=${encodeURIComponent(uniqueId)}`;
};
