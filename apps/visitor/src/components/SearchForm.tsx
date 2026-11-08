import Link from "next/link";
import type { Filters } from "@/lib/search";
import { TYPE_LABEL } from "@/lib/format";

export default function SearchForm({ filters }: { filters: Filters }) {
  return (
    <form method="get" action="/" className="card search" role="search">
      {/* ZAI-38: al cambiar otros filtros se conserva la zona elegida en el mapa */}
      {filters.cerca && <input type="hidden" name="cerca" value={`${filters.cerca.lat},${filters.cerca.lng}`} />}
      {filters.tiempo && <input type="hidden" name="tiempo" value={filters.tiempo} />}
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
