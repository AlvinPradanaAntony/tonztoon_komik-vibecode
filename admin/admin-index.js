(function () {
  "use strict";

  TonztoonAdmin.mountShell();

  const state = {
    apiBase: "http://127.0.0.1:8000",
    token: "",
    loading: { login: false },
  };
  const elements = {
    bootView: document.querySelector("#bootView"),
    loginView: document.querySelector("#loginView"),
    appView: document.querySelector("#appView"),
    loginForm: document.querySelector("#loginForm"),
    loginBtn: document.querySelector("#loginBtn"),
    apiBaseField: document.querySelector("#apiBaseField"),
    loginEmailField: document.querySelector("#loginEmailField"),
    loginPasswordField: document.querySelector("#loginPasswordField"),
    apiBaseLabel: document.querySelector("#apiBaseLabel"),
    logoutBtn: document.querySelector("#logoutBtn"),
  };

  const session = TonztoonAdmin.createSession({
    state,
    elements,
    setLoginLoading,
    onAuthenticated: verifyAdminAccess,
  });

  elements.loginForm.addEventListener("submit", session.login);
  elements.logoutBtn.addEventListener("click", session.logout);

  /* Sidebar logout */
  document.addEventListener("click", (event) => {
    const toggle = event.target.closest("[data-toggle-password]");
    if (toggle) TonztoonAdmin.togglePassword(toggle);

    const sidebarAction = event.target.closest("[data-sidebar-action]");
    if (sidebarAction?.dataset.sidebarAction === "logout") {
      session.logout();
    }
  });

  session.restoreSession();
  elements.loginView.classList.add("hidden");
  lucide.createIcons();
  if (state.token) {
    verifyStoredSession();
  } else {
    session.showLogin();
  }

  async function verifyStoredSession() {
    const allowed = await verifyAdminAccess();
    if (allowed) session.showApp();
  }

  async function verifyAdminAccess() {
    try {
      await session.apiFetch(
        "/api/v1/account-manager/accounts?page=1&per_page=1",
      );
      return true;
    } catch (error) {
      session.handleRequestError(error, "Akun ini tidak memiliki akses admin.");
      return false;
    }
  }

  function setLoginLoading(value) {
    state.loading.login = value;
    TonztoonAdmin.setButtonLoading(elements.loginBtn, value, {
      loadingText: "Memproses...",
      idleText: "Masuk",
      loadingIcon: "loader-2",
      idleIcon: "log-in",
    });
    lucide.createIcons();
  }
})();
