import { BrowserRouter, Route, Routes } from "react-router-dom";
import { AuthProvider } from "./auth/AuthProvider";
import Layout, { HomeRedirect, RequireRole } from "./components/Layout";
import Login from "./pages/Login";
import MisPropiedades from "./pages/MisPropiedades";
import PropertyForm from "./pages/PropertyForm";
import Solicitudes from "./pages/Solicitudes";
import MisAnuncios from "./pages/MisAnuncios";
import MiPerfil from "./pages/MiPerfil";
import MiPortafolio from "./pages/MiPortafolio";
import PostForm from "./pages/PostForm";

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
              path="/anuncios"
              element={
                <RequireRole roles={["vendedor"]}>
                  <MisAnuncios />
                </RequireRole>
              }
            />
            <Route
              path="/solicitudes"
              element={
                <RequireRole roles={["vendedor", "creativo", "admin"]}>
                  <Solicitudes />
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
            <Route
              path="/portafolio"
              element={
                <RequireRole roles={["creativo"]}>
                  <MiPortafolio />
                </RequireRole>
              }
            />
            <Route
              path="/portafolio/nueva"
              element={
                <RequireRole roles={["creativo"]}>
                  <PostForm />
                </RequireRole>
              }
            />
            <Route
              path="/portafolio/:id"
              element={
                <RequireRole roles={["creativo"]}>
                  <PostForm />
                </RequireRole>
              }
            />
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
