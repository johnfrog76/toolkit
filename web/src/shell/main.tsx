import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router";
import { Provider } from "react-redux";
import { store } from "./store";
import App from "./App.tsx";
import { ConfettiProvider } from "./ConfettiProvider";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <Provider store={store}>
      <BrowserRouter>
        <ConfettiProvider>
          <App />
        </ConfettiProvider>
      </BrowserRouter>
    </Provider>
  </React.StrictMode>,
);
