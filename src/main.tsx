import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import SuperAdminPortal from "./SuperAdminPortal";
import "./styles.css";
import "./modern-theme.css";
import "./executive-dashboard.css";
import "./oracle-classic-dashboard.css";

if ("serviceWorker" in navigator && import.meta.env.PROD) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").catch(error => console.error("Service worker registration failed:", error));
  });
}

const isPlatformPortal = window.location.pathname.replace(/\/$/, "") === "/super-admin";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>{isPlatformPortal ? <SuperAdminPortal /> : <App />}</React.StrictMode>
);
