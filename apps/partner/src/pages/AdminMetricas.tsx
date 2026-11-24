import { useEffect, useState } from "react";
import { friendlyError } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";

// RF-ADM-03: MRR global, churn y leads desbloqueados, mes por mes (migración 0021).
type Month = {
  month: string;
  mrr: number;
  active_subs: number;
  new_subs: number;
  churned: number;
  churn_pct: number | null;
  leads_unlocked: number;
  leads_by_credit: number;
  leads_by_payment: number;
  revenue: number;
};

const mxn = new Intl.NumberFormat("es-MX", { style: "currency", currency: "MXN", maximumFractionDigits: 0 });
const monthFmt = new Intl.DateTimeFormat("es-MX", { month: "long", year: "numeric", timeZone: "UTC" });

export default function AdminMetricas() {
  const [rows, setRows] = useState<Month[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    supabase.rpc("admin_metrics", { p_months: 6 }).then(({ data, error }) => {
      if (error) setError(friendlyError(error));
      setRows(
        ((data as Month[]) ?? []).map((m) => ({
          ...m,
          mrr: Number(m.mrr),
          revenue: Number(m.revenue),
          churn_pct: m.churn_pct === null ? null : Number(m.churn_pct),
          active_subs: Number(m.active_subs),
          new_subs: Number(m.new_subs),
          churned: Number(m.churned),
          leads_unlocked: Number(m.leads_unlocked),
          leads_by_credit: Number(m.leads_by_credit),
          leads_by_payment: Number(m.leads_by_payment),
        })),
      );
    });
  }, []);

  const now = rows?.[0];
  const maxMrr = Math.max(1, ...(rows ?? []).map((r) => r.mrr));

  return (
    <section>
      <h1>Métricas</h1>
      <p className="muted">
        MRR = lo que entra cada mes por suscripciones vivas (Pro y Enterprise). Churn = suscripciones que se cancelaron en el mes, sobre las que había al
        empezarlo; un cambio de plan no cuenta. Leads = contactos desbloqueados, con crédito o con pago.
      </p>
      {error && <p className="error">{error}</p>}
      {rows === null && !error && <p>Cargando…</p>}
      {now && (
        <div className="plans">
          <div className="card">
            <p className="muted small">MRR este mes</p>
            <h2>{mxn.format(now.mrr)}</h2>
            <p className="small">{now.active_subs} suscripciones vivas</p>
          </div>
          <div className="card">
            <p className="muted small">Churn este mes</p>
            <h2>{now.churn_pct === null ? "—" : `${now.churn_pct}%`}</h2>
            <p className="small">{now.churned} cancelaciones · {now.new_subs} nuevas</p>
          </div>
          <div className="card">
            <p className="muted small">Leads desbloqueados este mes</p>
            <h2>{now.leads_unlocked}</h2>
            <p className="small">{now.leads_by_credit} con crédito · {now.leads_by_payment} pagados</p>
          </div>
        </div>
      )}
      {rows && rows.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>Mes</th>
              <th>MRR</th>
              <th>Churn</th>
              <th>Leads</th>
              <th>Cobrado</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.month}>
                <td>{monthFmt.format(new Date(r.month))}</td>
                <td>
                  {mxn.format(r.mrr)}
                  <div style={{ height: 6, width: 120, background: "#eee", borderRadius: 3, marginTop: 4 }} aria-hidden>
                    <div style={{ height: 6, width: `${(r.mrr / maxMrr) * 100}%`, background: "var(--brand, #c9a876)", borderRadius: 3 }} />
                  </div>
                </td>
                <td>{r.churn_pct === null ? "—" : `${r.churn_pct}%`} <span className="muted small">({r.churned})</span></td>
                <td>{r.leads_unlocked}</td>
                <td>{mxn.format(r.revenue)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}
