import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, Coins, Check } from 'lucide-react';
import { Button } from './ui/button';
import { Input } from './ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from './ui/table';
import { useAuth } from './AuthProvider';
import { awardPoints, fetchAllCustomers, CustomerSearchResult } from '../lib/db/points';

const SUCCESS_DISPLAY_MS = 2000;

interface RowState {
  amountSpent: string;
  points: string;
  busy: boolean;
  error: string;
  success: boolean;
}

const emptyRowState: RowState = { amountSpent: '', points: '', busy: false, error: '', success: false };

export const AwardPointsPage: React.FC = () => {
  const { logout } = useAuth();
  const navigate = useNavigate();

  const [customers, setCustomers] = useState<CustomerSearchResult[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterQuery, setFilterQuery] = useState('');
  const [rows, setRows] = useState<Record<string, RowState>>({});
  const successTimeouts = useRef<Record<string, number>>({});

  useEffect(() => {
    let active = true;
    void (async () => {
      const found = await fetchAllCustomers();
      if (!active) return;
      setCustomers(found);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    return () => {
      (Object.values(successTimeouts.current) as number[]).forEach((id) => window.clearTimeout(id));
    };
  }, []);

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  const filteredCustomers = useMemo(() => {
    const term = filterQuery.trim().toLowerCase();
    if (!term) return customers;
    return customers.filter((customer) =>
      (customer.fullName ?? '').toLowerCase().includes(term) || customer.email.toLowerCase().includes(term)
    );
  }, [customers, filterQuery]);

  const getRow = (id: string): RowState => rows[id] ?? emptyRowState;

  const updateRow = (id: string, patch: Partial<RowState>) => {
    setRows((prev) => ({ ...prev, [id]: { ...(prev[id] ?? emptyRowState), ...patch } }));
  };

  const handleAward = async (customer: CustomerSearchResult) => {
    const row = getRow(customer.id);
    const amountSpentValue = Number(row.amountSpent);
    const pointsValue = Number(row.points);

    if (!row.amountSpent.trim() || !Number.isFinite(amountSpentValue) || amountSpentValue <= 0) {
      updateRow(customer.id, { error: 'Enter a valid amount spent.', success: false });
      return;
    }
    if (!Number.isInteger(pointsValue) || pointsValue === 0) {
      updateRow(customer.id, { error: 'Enter a non-zero whole number of points.', success: false });
      return;
    }

    updateRow(customer.id, { busy: true, error: '', success: false });
    const result = await awardPoints({
      customerId: customer.id,
      points: pointsValue,
      description: `Awarded for spending $${row.amountSpent.trim()}`,
    });

    if (!result.ok) {
      updateRow(customer.id, { busy: false, error: result.error ?? 'Unable to award points right now. Please try again.' });
      return;
    }

    updateRow(customer.id, { busy: false, error: '', success: true, amountSpent: '', points: '' });
    const existingTimeout = successTimeouts.current[customer.id];
    if (existingTimeout) window.clearTimeout(existingTimeout);
    successTimeouts.current[customer.id] = window.setTimeout(() => {
      updateRow(customer.id, { success: false });
      delete successTimeouts.current[customer.id];
    }, SUCCESS_DISPLAY_MS);
  };

  return (
    <div className="min-h-screen bg-gray-50/50">
      <header className="flex items-center justify-between border-b bg-white px-4 py-3 md:px-8">
        <div className="flex items-center gap-3">
          <div className="rounded-xl bg-primary p-2.5 text-primary-foreground shadow-md">
            <Coins size={20} />
          </div>
          <div className="text-lg font-bold text-foreground">Award Points</div>
        </div>
        <Button variant="ghost" onClick={handleLogout}>
          Log Out
        </Button>
      </header>

      <div className="mx-auto max-w-5xl space-y-4 p-4 md:p-8">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" size={16} />
          <Input
            className="max-w-sm pl-9"
            placeholder="Filter by name or email..."
            value={filterQuery}
            onChange={(e) => setFilterQuery(e.target.value)}
          />
        </div>

        <div className="rounded-xl border bg-white overflow-auto shadow-sm">
          <Table>
            <TableHeader>
              <TableRow className="bg-muted/30">
                <TableHead>Customer</TableHead>
                <TableHead className="w-[160px]">Amount Spent ($)</TableHead>
                <TableHead className="w-[160px]">Points to Award</TableHead>
                <TableHead className="w-[140px]" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {loading ? (
                <TableRow>
                  <TableCell colSpan={4} className="text-center h-32">
                    <div className="flex justify-center">
                      <div className="h-6 w-6 animate-spin rounded-full border-4 border-primary border-t-transparent" />
                    </div>
                  </TableCell>
                </TableRow>
              ) : filteredCustomers.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={4} className="text-center h-32 text-muted-foreground">
                    {customers.length === 0 ? 'No customers found.' : 'No customers match your filter.'}
                  </TableCell>
                </TableRow>
              ) : (
                filteredCustomers.map((customer) => {
                  const row = getRow(customer.id);
                  return (
                    <TableRow key={customer.id} className="hover:bg-muted/30 transition-colors align-top">
                      <TableCell>
                        <div className="font-medium text-foreground">{customer.fullName ?? 'Customer'}</div>
                        <div className="text-xs text-muted-foreground">{customer.email}</div>
                      </TableCell>
                      <TableCell>
                        <Input
                          type="number"
                          step="0.01"
                          placeholder="e.g. 25.00"
                          value={row.amountSpent}
                          onChange={(e) => updateRow(customer.id, { amountSpent: e.target.value, error: '' })}
                        />
                      </TableCell>
                      <TableCell>
                        <Input
                          type="number"
                          step="1"
                          placeholder="e.g. 150"
                          value={row.points}
                          onChange={(e) => updateRow(customer.id, { points: e.target.value, error: '' })}
                        />
                      </TableCell>
                      <TableCell>
                        <div className="flex flex-col items-start gap-1">
                          <Button
                            size="sm"
                            disabled={row.busy}
                            onClick={() => handleAward(customer)}
                          >
                            {row.busy ? 'Awarding...' : 'Award'}
                          </Button>
                          {row.success && (
                            <span className="flex items-center gap-1 text-xs font-medium text-emerald-600">
                              <Check size={14} /> Awarded
                            </span>
                          )}
                          {row.error && (
                            <span className="text-xs font-medium text-rose-600">{row.error}</span>
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  );
                })
              )}
            </TableBody>
          </Table>
        </div>
      </div>
    </div>
  );
};
