import Link from "next/link";
import type { Filters } from "@/lib/search";
import { TYPE_LABEL } from "@/lib/format";

/** ZAI-24 · Formulario de filtros. Usa GET, así los filtros quedan en la URL. */
export default function SearchForm({ filters }: { filters: Filters }) {
  return (
    <form method="get" action="/" className="card search" role="search">
      <label>
        Ubicación
        <input name="ubicacion" defaultValue={filters.ubicacion} placeholder="Ciudad, estado o colonia" />
      </label>
      <label>
        Tipo
        <select name="tipo" defaultValue={filters.tipo ?? ""}>
          <option value="">Todos</option>
          {Object.entries(TYPE_LABEL).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </label>
      <label>
        Operación
        <select name="operacion" defaultValue={filters.operacion ?? ""}>
          <option value="">Venta y renta</option>
          <option value="venta">Venta</option>
          <option value="renta">Renta</option>
        </select>
      </label>
      <label>
        Precio mínimo
        <input name="min" type="number" min="0" step="1000" defaultValue={filters.min} placeholder="$" />
      </label>
      <label>
        Precio máximo
        <input name="max" type="number" min="0" step="1000" defaultValue={filters.max} placeholder="$" />
      </label>
      <div className="search-actions">
        <button type="submit" className="primary">
          Buscar
        </button>
        <Link href="/" className="button">
          Limpiar
        </Link>
      </div>
    </form>
  );
}
