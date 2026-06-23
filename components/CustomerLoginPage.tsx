import React, { useState } from 'react';
import { Link, Navigate, useLocation } from 'react-router-dom';
import { Input } from './ui/input';
import { Label } from './ui/label';
import { Button } from './ui/button';
import { useAuth } from './AuthProvider';
import type { AuthResult } from './AuthProvider';
import { CustomerNavHeader } from './CustomerNavHeader';
import { isSupabaseConfigured } from '../lib/supabase';

const SERVICE_UNAVAILABLE_MESSAGE = 'Service is temporarily unavailable. Please try again later.';

export const CustomerLoginPage: React.FC = () => {
  const { currentUser, loading, login } = useAuth();
  const location = useLocation();
  const fromPath = (location.state as { from?: { pathname?: string } })?.from?.pathname;

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  if (!isSupabaseConfigured) {
    return (
      <div className="h-screen flex items-center justify-center px-6 text-center text-muted-foreground">
        {SERVICE_UNAVAILABLE_MESSAGE}
      </div>
    );
  }

  if (!loading && currentUser?.role === 'customer' && fromPath) {
    return <Navigate to={fromPath} replace />;
  }

  if (!loading && currentUser?.role === 'customer' && !fromPath) {
    return (
      <div className="min-h-screen bg-[#f5f5f7] px-4 py-10 sm:px-6 sm:py-14">
        <CustomerNavHeader />
      <div className="mx-auto w-full max-w-xl text-center">
          <section className="rounded-[2rem] border border-black/[0.08] bg-white p-8 shadow-[0_24px_64px_-38px_rgba(0,0,0,0.35)]">
            <h1 className="text-2xl font-black tracking-[-0.02em] text-[#1d1d1f]">
              You're logged in, {currentUser.fullName ?? 'there'}.
            </h1>
            <p className="mt-3 text-[0.98rem] leading-7 text-[#4f5258]">
              Scan a venue's QR code on the counter to claim your discount.
            </p>
          </section>
        </div>
      </div>
    );
  }

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError('');
    setSubmitting(true);
    const result: AuthResult = await login(email, password);
    setSubmitting(false);
    if ('error' in result) {
      setError(result.error);
    }
    // Redirect happens automatically once currentUser is set.
  };

  return (
    <div className="min-h-screen bg-[#f5f5f7] px-4 py-10 sm:px-6 sm:py-14">
      <div className="mx-auto w-full max-w-xl">
        <section className="rounded-[2rem] border border-black/[0.08] bg-white p-6 shadow-[0_24px_64px_-38px_rgba(0,0,0,0.35)] sm:p-8">
          <p className="text-[0.68rem] font-semibold uppercase tracking-[0.26em] text-[#6e6e73]">Discount Network</p>
          <h1 className="mt-3 text-[clamp(1.9rem,5vw,2.7rem)] font-black leading-[0.96] tracking-[-0.03em] text-[#1d1d1f]">
            Welcome back
          </h1>
          <p className="mt-3 text-[0.98rem] leading-7 text-[#4f5258]">
            Log in to claim your discount at this venue.
          </p>

          <form onSubmit={handleSubmit} className="mt-6 space-y-5">
            <div className="grid gap-2">
              <Label htmlFor="email" className="text-sm font-medium text-[#1d1d1f]">Email</Label>
              <Input
                id="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                type="email"
                autoComplete="email"
                required
                className="h-12 rounded-xl border-black/10 text-[#1d1d1f] placeholder:text-[#8f9197]"
              />
            </div>

            <div className="grid gap-2">
              <Label htmlFor="password" className="text-sm font-medium text-[#1d1d1f]">Password</Label>
              <Input
                id="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Your password"
                type="password"
                autoComplete="current-password"
                required
                className="h-12 rounded-xl border-black/10 text-[#1d1d1f] placeholder:text-[#8f9197]"
              />
            </div>

            {error && (
              <div className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
                {error}
              </div>
            )}

            <Button
              type="submit"
              className="h-12 w-full rounded-xl bg-[#1d1d1f] text-sm font-semibold text-white hover:bg-black/85"
              disabled={submitting}
            >
              {submitting ? 'Signing in...' : 'Log In'}
            </Button>

            <p className="text-center text-sm text-[#6e6e73]">
              Don't have an account?{' '}
              <Link to="/customer/signup" className="font-semibold text-[#1d1d1f] underline-offset-2 hover:underline">
                Sign up
              </Link>
            </p>
          </form>
        </section>
      </div>
    </div>
  );
};
