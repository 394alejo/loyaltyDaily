import React, { useState } from 'react';
import { Link, Navigate, useNavigate } from 'react-router-dom';
import { Input } from './ui/input';
import { Label } from './ui/label';
import { Button } from './ui/button';
import { useAuth } from './AuthProvider';
import { isSupabaseConfigured } from '../lib/supabase';

const SERVICE_UNAVAILABLE_MESSAGE = 'Service is temporarily unavailable. Please try again later.';

export const CustomerSignupPage: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser, loading, signupCustomer } = useAuth();

  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [submitting, setSubmitting] = useState(false);

  if (!loading && currentUser) {
    return <Navigate to={currentUser.role === 'customer' ? '/customer/login' : '/dashboard'} replace />;
  }

  if (!isSupabaseConfigured) {
    return (
      <div className="h-screen flex items-center justify-center px-6 text-center text-muted-foreground">
        {SERVICE_UNAVAILABLE_MESSAGE}
      </div>
    );
  }

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError('');
    setMessage('');

    if (!fullName.trim()) {
      setError('Full name is required.');
      return;
    }
    if (password.length < 6) {
      setError('Password must be at least 6 characters.');
      return;
    }

    setSubmitting(true);
    const result = await signupCustomer({ fullName, email, password });
    setSubmitting(false);

    if (!result.ok) {
      setError(result.error);
      return;
    }
    if (result.message) {
      setMessage(result.message);
      return;
    }
    navigate('/customer/login', { replace: true });
  };

  return (
    <div className="min-h-screen bg-[#f5f5f7] px-4 py-10 sm:px-6 sm:py-14">
      <div className="mx-auto w-full max-w-xl">
        <section className="rounded-[2rem] border border-black/[0.08] bg-white p-6 shadow-[0_24px_64px_-38px_rgba(0,0,0,0.35)] sm:p-8">
          <p className="text-[0.68rem] font-semibold uppercase tracking-[0.26em] text-[#6e6e73]">Discount Network</p>
          <h1 className="mt-3 text-[clamp(1.9rem,5vw,2.7rem)] font-black leading-[0.96] tracking-[-0.03em] text-[#1d1d1f]">
            Create your account
          </h1>
          <p className="mt-3 text-[0.98rem] leading-7 text-[#4f5258]">
            One account gets you discounts at every venue in the network.
          </p>

          <form onSubmit={handleSubmit} className="mt-6 space-y-5">
            <div className="grid gap-2">
              <Label htmlFor="fullName" className="text-sm font-medium text-[#1d1d1f]">Full Name</Label>
              <Input
                id="fullName"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="Your full name"
                autoComplete="name"
                required
                className="h-12 rounded-xl border-black/10 text-[#1d1d1f] placeholder:text-[#8f9197]"
              />
            </div>

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
                placeholder="At least 6 characters"
                type="password"
                autoComplete="new-password"
                required
                className="h-12 rounded-xl border-black/10 text-[#1d1d1f] placeholder:text-[#8f9197]"
              />
            </div>

            {error && (
              <div className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
                {error}
              </div>
            )}
            {message && (
              <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
                {message}
              </div>
            )}

            <Button
              type="submit"
              className="h-12 w-full rounded-xl bg-[#1d1d1f] text-sm font-semibold text-white hover:bg-black/85"
              disabled={submitting}
            >
              {submitting ? 'Creating your account...' : 'Create Account'}
            </Button>

            <p className="text-center text-sm text-[#6e6e73]">
              Already have an account?{' '}
              <Link to="/customer/login" className="font-semibold text-[#1d1d1f] underline-offset-2 hover:underline">
                Log in
              </Link>
            </p>
          </form>
        </section>
      </div>
    </div>
  );
};
