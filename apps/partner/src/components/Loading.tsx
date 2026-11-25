// Estado de carga con el estilo BINCA: barras que "respiran" en vez de un texto suelto.
// `full` lo centra en toda la pantalla (cuando todavía no hay menú).
export default function Loading({ label = "Cargando…", rows = 3, full = false }: { label?: string; rows?: number; full?: boolean }) {
  return (
    <div className={full ? "loading loading-full" : "loading"} role="status" aria-live="polite">
      <div className="card loading-card" aria-hidden="true">
        {Array.from({ length: rows }, (_, i) => (
          <div key={i} className="sk-row">
            <span className="sk" style={{ width: `${60 - i * 8}%` }} />
            <span className="sk" />
            <span className="sk" />
          </div>
        ))}
      </div>
      <p className="muted">{label}</p>
    </div>
  );
}
