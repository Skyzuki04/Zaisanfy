import { BrowserRouter, Route, Routes } from "react-router-dom";
import { AuthProvider } from "./auth/AuthProvider";
import Layout, { HomeRedirect, RequireRole } from "./components/Layout";
import Login from "./pages/Login";
import MisPropiedades from "./pages/MisPropiedades";
import PropertyForm from "./pages/PropertyForm";
import MiPerfil from "./pages/MiPerfil";

// Consola de socios (App 2): vendedores y creativos.
export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/entrar" element={<Login />} />
          <Route element={<Layout />}>
            <Route index element={<HomeRedirect />} />
            <Route
              path="/propiedades"
              element={
                <RequireRole roles={["vendedor", "admin"]}>
                  <MisPropiedades />
                </RequireRole>
              }
            />
            <Route
              path="/propiedades/nueva"
              element={
                <RequireRole roles={["vendedor"]}>
                  <PropertyForm />
                </RequireRole>
              }
            />
            <Route
              path="/propiedades/:id"
              element={
                <RequireRole roles={["vendedor", "admin"]}>
                  <PropertyForm />
                </RequireRole>
              }
            />
            <Route
              path="/perfil"
              element={
                <RequireRole roles={["creativo"]}>
                  <MiPerfil />
                </RequireRole>
              }
            />
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
