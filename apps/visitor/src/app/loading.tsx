// Se muestra mientras el servidor arma la página (por ejemplo, mientras busca propiedades)
export default function Loading() {
  return (
    <main className="page" aria-busy="true">
      <div className="section-title">
        <div>
          <span className="eyebrow">Zaisanfy</span>
          <h2>Cargando…</h2>
        </div>
      </div>
      <ul className="cards" aria-hidden="true">
        {Array.from({ length: 6 }, (_, i) => (
          <li key={i} className="sk-card">
            <div className="sk sk-img" />
            <div className="sk sk-line" style={{ width: "70%" }} />
            <div className="sk sk-line" style={{ width: "45%" }} />
            <div className="sk sk-line sk-price" />
          </li>
        ))}
      </ul>
      <p className="sr-only" role="status">
        Cargando la página
      </p>
    </main>
  );
}
