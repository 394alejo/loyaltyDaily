import React, { useEffect, useState } from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { useAuth } from './AuthProvider';
import { cn } from '../lib/utils';
import { fetchPointsBalance } from '../lib/db/points';
import { isSupabaseConfigured } from '../lib/supabase';

export const CustomerNavHeader: React.FC = () => {
  const { currentUser, logout } = useAuth();
  const navigate = useNavigate();
  const [balance, setBalance] = useState<number | null>(null);

  useEffect(() => {
    if (!isSupabaseConfigured || !currentUser) return;
    let active = true;
    void (async () => {
      const result = await fetchPointsBalance(currentUser.id);
      if (active) setBalance(result);
    })();
    return () => {
      active = false;
    };
  }, [currentUser]);

  const handleLogout = async () => {
    await logout();
    navigate('/customer/login');
  };

  return (
    <div className="mx-auto mb-6 flex w-full max-w-xl items-center justify-between">
      <div className="flex items-center gap-2 text-sm font-semibold text-[#1d1d1f]">
        {currentUser?.fullName ?? 'My Account'}
        {balance != null && (
          <span className="rounded-full bg-[#1d1d1f]/[0.06] px-2.5 py-0.5 text-[0.7rem] font-bold text-[#1d1d1f]">
            {balance.toLocaleString()} pts
          </span>
        )}
      </div>
      <div className="flex items-center gap-4 text-[0.8rem] font-medium">
        <NavLink
          to="/customer/visits"
          className={({ isActive }) =>
            cn('text-[#6e6e73] hover:text-[#1d1d1f]', isActive && 'text-[#1d1d1f] underline underline-offset-4')
          }
        >
          My Visits
        </NavLink>
        <NavLink
          to="/customer/points"
          className={({ isActive }) =>
            cn('text-[#6e6e73] hover:text-[#1d1d1f]', isActive && 'text-[#1d1d1f] underline underline-offset-4')
          }
        >
          My Points
        </NavLink>
        <button onClick={handleLogout} className="text-[#6e6e73] hover:text-[#1d1d1f]">
          Log Out
        </button>
      </div>
    </div>
  );
};
