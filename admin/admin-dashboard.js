(function () {
  "use strict";

  const SESSION_KEY = "tonztoon.account-manager.session.v2";
  const DEFAULT_API_BASE = "http://127.0.0.1:8000";

  window.tailwind = window.tailwind || {};
  window.tailwind.config = {
    theme: {
      extend: {
        colors: {
          ink: "#161a1d",
          muted: "#667085",
          line: "#d9dee5",
          paper: "#f7f8fa",
          brand: "#0f766e",
          accent: "#b42318",
        },
        boxShadow: {
          soft: "0 14px 40px rgba(16, 24, 40, 0.08)",
        },
      },
    },
  };

  function mountShell() {
    document.querySelectorAll("[data-admin-login]").forEach((element) => {
      const title = element.dataset.title || "Admin Dashboard";
      const description =
        element.dataset.description || "Masuk menggunakan akun administrator.";
      const visibilityClass = element.classList.contains("hidden")
        ? "hidden "
        : "";
      element.className = `${visibilityClass}grid min-h-screen place-items-center px-4 py-8`;
      element.innerHTML = `
        <form id="loginForm" class="glass-panel w-full max-w-md rounded-3xl border border-white/70 p-6 shadow-soft">
          <div class="mb-5">
            <p class="text-xs font-semibold uppercase tracking-[0.18em] text-brand">Admin</p>
            <h1 class="mt-1 text-2xl font-semibold text-ink">${escapeHtml(title)}</h1>
            <p class="mt-2 text-sm leading-6 text-muted">${escapeHtml(description)}</p>
          </div>
          <label class="block">
            <span class="text-sm font-medium text-ink">Backend API base URL</span>
            <input id="apiBaseField" type="url" class="mt-1 h-11 w-full rounded-2xl border border-line bg-white/90 px-3 text-sm outline-none focus:border-brand focus:ring-2 focus:ring-brand/20" value="${DEFAULT_API_BASE}" />
          </label>
          <label class="mt-4 block">
            <span class="text-sm font-medium text-ink">Email admin</span>
            <input id="loginEmailField" type="email" required class="mt-1 h-11 w-full rounded-2xl border border-line bg-white/90 px-3 text-sm outline-none focus:border-brand focus:ring-2 focus:ring-brand/20" />
          </label>
          <label class="mt-4 block">
            <span class="text-sm font-medium text-ink">Password</span>
            <div class="relative mt-1">
              <input id="loginPasswordField" type="password" required minlength="8" class="h-11 w-full rounded-2xl border border-line bg-white/90 pl-3 pr-10 text-sm outline-none focus:border-brand focus:ring-2 focus:ring-brand/20" />
              <button type="button" data-toggle-password="loginPasswordField" class="absolute right-1 top-1/2 inline-flex h-10 w-10 -translate-y-1/2 items-center justify-center rounded-xl text-muted hover:bg-slate-50 hover:text-ink" title="Lihat password">
                <i data-lucide="eye" class="eye-icon h-4 w-4"></i>
                <i data-lucide="eye-off" class="eye-off-icon hidden h-4 w-4"></i>
              </button>
            </div>
          </label>
          <button id="loginBtn" type="submit" class="admin-login-button mt-5 inline-flex h-11 w-full items-center justify-center gap-2 rounded-2xl px-4 text-sm font-semibold text-white">
            <i data-lucide="log-in" class="h-4 w-4"></i>
            <span>Masuk</span>
          </button>
        </form>
      `;
    });

    document.querySelectorAll("[data-admin-header]").forEach((element) => {
      const eyebrow = element.dataset.eyebrow || "Admin";
      const title = element.dataset.title || "Dashboard";
      const actions =
        element.querySelector("template[data-admin-actions]")?.innerHTML || "";
      element.className =
        "sticky top-0 z-30 border-b border-white/70 bg-white/80 backdrop-blur-xl";
      element.innerHTML = `
        <div class="mx-auto flex max-w-7xl flex-col gap-4 px-4 py-4 sm:px-6 lg:flex-row lg:items-center lg:justify-between lg:px-8">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.18em] text-brand">${escapeHtml(eyebrow)}</p>
            <h1 class="mt-1 text-2xl font-semibold text-ink sm:text-3xl">${escapeHtml(title)}</h1>
            <p id="apiBaseLabel" class="mt-1 break-all text-xs text-muted"></p>
          </div>
          <div class="flex flex-wrap items-center gap-2">${actions}</div>
        </div>
      `;
    });
  }

  function createSession(options) {
    const state = options.state;
    const elements = options.elements;
    const setLoginLoading = options.setLoginLoading || (() => {});
    const onAuthenticated = options.onAuthenticated || (async () => true);
    const onLogout = options.onLogout || (() => {});
    const onTokenChanged = options.onTokenChanged || (() => {});

    function restoreSession() {
      try {
        const saved = JSON.parse(localStorage.getItem(SESSION_KEY) || "{}");
        state.apiBase = trimSlash(
          saved.apiBase || state.apiBase || DEFAULT_API_BASE,
        );
        state.token = saved.token || "";
      } catch {
        localStorage.removeItem(SESSION_KEY);
        state.apiBase = state.apiBase || DEFAULT_API_BASE;
        state.token = "";
      }
      elements.apiBaseField.value = state.apiBase;
      onTokenChanged(state.token);
    }

    function persistSession() {
      localStorage.setItem(
        SESSION_KEY,
        JSON.stringify({ apiBase: state.apiBase, token: state.token }),
      );
    }

    function showLogin() {
      elements.bootView?.classList.add("hidden");
      elements.loginView.classList.remove("hidden");
      elements.appView.classList.add("hidden");
    }

    function showApp() {
      elements.bootView?.classList.add("hidden");
      elements.loginView.classList.add("hidden");
      elements.appView.classList.remove("hidden");
      elements.apiBaseLabel.textContent = state.apiBase;
    }

    async function login(event) {
      event.preventDefault();
      if (state.loading.login) return;
      state.apiBase = trimSlash(
        elements.apiBaseField.value.trim() || state.apiBase || DEFAULT_API_BASE,
      );
      setLoginLoading(true);
      try {
        const payload = await request(
          "/api/v1/auth/login",
          {
            method: "POST",
            body: {
              email: elements.loginEmailField.value.trim(),
              password: elements.loginPasswordField.value,
            },
          },
          false,
        );
        state.token = payload.session?.access_token || "";
        if (!state.token) {
          throw new Error(
            payload.message || "Login berhasil tetapi token tidak diterima.",
          );
        }
        onTokenChanged(state.token);
        const allowed = await onAuthenticated();
        if (allowed) {
          persistSession();
          showApp();
          notify("Login berhasil.");
        }
      } catch (error) {
        notify(error.message, true);
      } finally {
        setLoginLoading(false);
      }
    }

    function logout() {
      state.token = "";
      localStorage.removeItem(SESSION_KEY);
      onTokenChanged("");
      onLogout();
      showLogin();
    }

    async function request(path, requestOptions = {}, authorized = true) {
      const headers = {
        "Content-Type": "application/json",
        ...(requestOptions.headers || {}),
      };
      if (authorized) headers.Authorization = `Bearer ${state.token}`;

      let response;
      try {
        response = await fetch(`${state.apiBase}${path}`, {
          method: requestOptions.method || "GET",
          headers,
          body: requestOptions.body
            ? JSON.stringify(requestOptions.body)
            : undefined,
        });
      } catch {
        throw new Error(
          "Gagal terhubung ke server. Pastikan API URL benar dan server sedang berjalan.",
        );
      }

      let payload = {};
      try {
        payload = await response.json();
      } catch {
        payload = {};
      }
      if (!response.ok) {
        const detail = payload.detail;
        const message =
          payload.message ||
          (typeof detail === "object" ? detail?.message : detail) ||
          `Request gagal (${response.status}).`;
        const error = new Error(message);
        error.status = response.status;
        throw error;
      }
      return payload;
    }

    function handleRequestError(error, accessMessage) {
      if (error.status === 401 || error.status === 403) {
        notify(
          error.message || accessMessage || "Sesi admin tidak valid.",
          true,
        );
        logout();
        return;
      }
      notify(error.message || "Request gagal.", true);
    }

    return {
      apiFetch: (path, requestOptions = {}) =>
        request(path, requestOptions, true),
      handleRequestError,
      login,
      logout,
      persistSession,
      publicFetch: (path, requestOptions = {}) =>
        request(path, requestOptions, false),
      request,
      restoreSession,
      showApp,
      showLogin,
    };
  }

  function createFeatureSession(options) {
    const state = options.state;
    const loginUrl = options.loginUrl || "./index.html";
    const onLogout = options.onLogout || (() => {});
    const onTokenChanged = options.onTokenChanged || (() => {});

    function restoreSession() {
      try {
        const saved = JSON.parse(localStorage.getItem(SESSION_KEY) || "{}");
        state.apiBase = trimSlash(
          saved.apiBase || state.apiBase || DEFAULT_API_BASE,
        );
        state.token = saved.token || "";
      } catch {
        clearSession();
      }
      onTokenChanged(state.token);
      const hasSession = Boolean(state.token);
      if (!hasSession) redirectToLogin();
      return hasSession;
    }

    function clearSession() {
      state.token = "";
      localStorage.removeItem(SESSION_KEY);
      onTokenChanged("");
    }

    function redirectToLogin() {
      window.location.replace(loginUrl);
    }

    function logout() {
      clearSession();
      onLogout();
      redirectToLogin();
    }

    async function request(path, requestOptions = {}) {
      if (!state.token) {
        redirectToLogin();
        throw new Error("Sesi admin tidak tersedia.");
      }

      const headers = {
        "Content-Type": "application/json",
        Authorization: `Bearer ${state.token}`,
        ...(requestOptions.headers || {}),
      };
      let response;
      try {
        response = await fetch(`${state.apiBase}${path}`, {
          method: requestOptions.method || "GET",
          headers,
          body: requestOptions.body
            ? JSON.stringify(requestOptions.body)
            : undefined,
        });
      } catch {
        throw new Error(
          "Gagal terhubung ke server. Pastikan API URL benar dan server sedang berjalan.",
        );
      }

      let payload = {};
      try {
        payload = await response.json();
      } catch {
        payload = {};
      }
      if (!response.ok) {
        const detail = payload.detail;
        const message =
          payload.message ||
          (typeof detail === "object" ? detail?.message : detail) ||
          `Request gagal (${response.status}).`;
        const error = new Error(message);
        error.status = response.status;
        throw error;
      }
      return payload;
    }

    function handleRequestError(error, accessMessage) {
      if (error.status === 401 || error.status === 403) {
        notify(
          error.message || accessMessage || "Sesi admin tidak valid.",
          true,
        );
        window.setTimeout(logout, 500);
        return;
      }
      notify(error.message || "Request gagal.", true);
    }

    return {
      apiFetch: request,
      handleRequestError,
      logout,
      redirectToLogin,
      restoreSession,
    };
  }

  function setButtonLoading(button, isLoading, options) {
    if (!button) return;
    const normalized =
      typeof options === "string"
        ? {
            loadingText: options,
            idleText: arguments[3],
            loadingIcon: null,
            idleIcon: null,
          }
        : options;
    const icon = button.querySelector("[data-loading-icon], svg, i");
    const label = button.querySelector("span");
    button.disabled = Boolean(isLoading || normalized.disabled);
    if (label) {
      label.textContent = isLoading
        ? normalized.loadingText
        : normalized.idleText;
    }
    if (!icon) return;
    icon.classList.toggle("animate-spin", Boolean(isLoading));
    const iconName = isLoading ? normalized.loadingIcon : normalized.idleIcon;
    if (iconName) icon.setAttribute("data-lucide", iconName);
  }

  function togglePassword(button) {
    const input = document.getElementById(button.dataset.togglePassword);
    if (!input) return;
    const reveal = input.type === "password";
    input.type = reveal ? "text" : "password";
    button.querySelector(".eye-icon")?.classList.toggle("hidden", reveal);
    button.querySelector(".eye-off-icon")?.classList.toggle("hidden", !reveal);
    button.title = reveal ? "Sembunyikan password" : "Lihat password";
  }

  function userIdFromToken(token) {
    if (!token) return null;
    try {
      const payload = token.split(".")[1] || "";
      const padded = payload
        .replace(/-/g, "+")
        .replace(/_/g, "/")
        .padEnd(Math.ceil(payload.length / 4) * 4, "=");
      return JSON.parse(atob(padded)).sub || null;
    } catch {
      return null;
    }
  }

  function notify(message, isError = false) {
    const toastNode = document.createElement("div");
    toastNode.className = "admin-toast-card";
    toastNode.dataset.tone = isError ? "error" : "success";
    toastNode.innerHTML = `
      <span class="admin-toast-icon">
        <i data-lucide="${isError ? "alert-circle" : "check-circle-2"}" class="h-4 w-4"></i>
      </span>
      <span class="min-w-0">
        <p class="admin-toast-title">${isError ? "Terjadi kendala" : "Berhasil"}</p>
        <p class="admin-toast-message"></p>
      </span>
    `;
    toastNode.querySelector(".admin-toast-message").textContent = message;

    if (window.Toastify) {
      Toastify({
        node: toastNode,
        duration: isError ? 6200 : 4200,
        close: true,
        gravity: "top",
        position: "right",
        stopOnFocus: true,
        className: "admin-toast",
        ariaLive: isError ? "assertive" : "polite",
        style: { background: "transparent", boxShadow: "none" },
      }).showToast();
      window.lucide?.createIcons();
      return;
    }

    let region = document.querySelector("#fallbackToastRegion");
    if (!region) {
      region = document.createElement("div");
      region.id = "fallbackToastRegion";
      region.className = "fallback-toast-region";
      document.body.appendChild(region);
    }
    toastNode.setAttribute("role", "status");
    toastNode.setAttribute("aria-live", isError ? "assertive" : "polite");
    region.prepend(toastNode);
    window.lucide?.createIcons();
    setTimeout(() => toastNode.remove(), isError ? 6200 : 4200);
  }

  function trimSlash(value) {
    return String(value || "").replace(/\/+$/, "");
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  window.TonztoonAdmin = {
    createFeatureSession,
    createSession,
    escapeHtml,
    mountShell,
    notify,
    setButtonLoading,
    togglePassword,
    trimSlash,
    userIdFromToken,
  };
})();
