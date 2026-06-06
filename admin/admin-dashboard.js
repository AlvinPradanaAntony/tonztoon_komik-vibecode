(function () {
  "use strict";

  const SESSION_KEY = "tonztoon.account-manager.session.v2";
  const DEFAULT_API_BASE = "http://127.0.0.1:8000";

  /* ── Sidebar Configuration ──────────────────────────────────────────── */
  const SIDEBAR_LINKS = [
    { id: "dashboard", icon: "layout-grid", tooltip: "Dashboard", href: "./index.html" },
    { id: "accounts", icon: "users", tooltip: "Manajemen Akun", href: "./account-dashboard.html" },
    { id: "helpdesk", icon: "life-buoy", tooltip: "Helpdesk", href: "./helpdesk-dashboard.html" },
  ];

  const SIDEBAR_BOTTOM = [
    { id: "logout", icon: "log-out", tooltip: "Logout" },
  ];

  /* ── Shared Utilities ───────────────────────────────────────────────── */
  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function trimSlash(value) {
    return String(value || "").replace(/\/+$/, "");
  }

  function normalize(value) {
    return String(value || "").toLowerCase();
  }

  function formatDate(value) {
    if (!value) return "-";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return new Intl.DateTimeFormat("id-ID", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(date);
  }

  function blankPanel(text) {
    return `<div class="blank-panel">${escapeHtml(text)}</div>`;
  }

  function detailRow(label, value, mono = false) {
    return `
      <div class="detail-row">
        <dt>${escapeHtml(label)}</dt>
        <dd ${mono ? 'class="mono text-xs"' : ''} style="word-break:break-all">${escapeHtml(value)}</dd>
      </div>
    `;
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

  function animateCounter(element, target, duration = 600) {
    const start = parseInt(element.textContent, 10) || 0;
    if (start === target) return;
    const startTime = performance.now();
    function step(now) {
      const elapsed = now - startTime;
      const progress = Math.min(elapsed / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      element.textContent = Math.round(start + (target - start) * eased);
      if (progress < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }

  /* ── Mount Shell (Login, Header, Sidebar) ───────────────────────────── */
  function mountShell() {
    /* Login form */
    document.querySelectorAll("[data-admin-login]").forEach((element) => {
      const title = element.dataset.title || "Admin Dashboard";
      const description =
        element.dataset.description || "Masuk menggunakan akun administrator.";
      const visibilityClass = element.classList.contains("hidden")
        ? "hidden "
        : "";
      element.className = `${visibilityClass}login-page`;
      element.innerHTML = `
        <form id="loginForm" class="login-card">
          <div class="login-header">
            <p class="section-eyebrow" style="margin-bottom:8px">Admin</p>
            <h1>${escapeHtml(title)}</h1>
            <p>${escapeHtml(description)}</p>
          </div>
          <div class="login-fields">
            <div class="input-group">
              <label class="input-label" for="apiBaseField">Backend API base URL</label>
              <input id="apiBaseField" type="url" class="input" value="${DEFAULT_API_BASE}" />
            </div>
            <div class="input-group">
              <label class="input-label" for="loginEmailField">Email admin</label>
              <input id="loginEmailField" type="email" required class="input" />
            </div>
            <div class="input-group">
              <label class="input-label" for="loginPasswordField">Password</label>
              <div class="password-wrapper">
                <input id="loginPasswordField" type="password" required minlength="8" class="input" style="padding-right:44px" />
                <button type="button" data-toggle-password="loginPasswordField" class="password-toggle" title="Lihat password">
                  <i data-lucide="eye" class="eye-icon"></i>
                  <i data-lucide="eye-off" class="eye-off-icon hidden"></i>
                </button>
              </div>
            </div>
            <button id="loginBtn" type="submit" class="btn btn-primary w-full" style="height:44px;margin-top:4px">
              <i data-lucide="log-in"></i>
              <span>Masuk</span>
            </button>
          </div>
        </form>
      `;
    });

    /* Header */
    document.querySelectorAll("[data-admin-header]").forEach((element) => {
      const eyebrow = element.dataset.eyebrow || "Admin";
      const title = element.dataset.title || "Dashboard";
      const actions =
        element.querySelector("template[data-admin-actions]")?.innerHTML || "";
      element.className = "admin-header";
      element.innerHTML = `
        <div class="header-inner">
          <div class="header-left">
            <div class="header-title-container">
              <h1 class="header-title">${escapeHtml(title)}</h1>
              <div class="api-status-badge">
                <span class="pulse-dot"></span>
                <span id="apiBaseLabel" class="api-base-text"></span>
              </div>
            </div>
          </div>
          <div class="header-actions">${actions}</div>
        </div>
      `;
    });

    /* Sidebar */
    document.querySelectorAll("[data-admin-sidebar]").forEach((element) => {
      const activeId = element.dataset.activeModule || "";
      element.className = "admin-sidebar";
      const navLinks = SIDEBAR_LINKS.map((link) =>
        `<a href="${link.href}" class="sidebar-link ${link.id === activeId ? 'active' : ''}" data-tooltip="${escapeHtml(link.tooltip)}">
          <i data-lucide="${link.icon}"></i>
        </a>`
      ).join("");
      const bottomLinks = SIDEBAR_BOTTOM.map((link) =>
        `<button type="button" class="sidebar-link" data-tooltip="${escapeHtml(link.tooltip)}" data-sidebar-action="${link.id}">
          <i data-lucide="${link.icon}"></i>
        </button>`
      ).join("");
      element.innerHTML = `
        <div class="sidebar-logo">
          <img src="./logo.png" alt="TonzToon" />
        </div>
        <nav class="sidebar-nav">${navLinks}</nav>
        <div class="sidebar-bottom">${bottomLinks}</div>
      `;
    });

    /* Sidebar toggle (mobile) */
    const sidebar = document.querySelector(".admin-sidebar");
    if (sidebar) {
      let toggle = document.querySelector("#sidebarToggle");
      let overlay = document.querySelector("#sidebarOverlay");
      if (!toggle) {
        toggle = document.createElement("button");
        toggle.id = "sidebarToggle";
        toggle.type = "button";
        toggle.className = "sidebar-toggle";
        toggle.innerHTML = '<i data-lucide="menu"></i>';
        document.body.appendChild(toggle);
      }
      if (!overlay) {
        overlay = document.createElement("div");
        overlay.id = "sidebarOverlay";
        overlay.className = "sidebar-overlay";
        document.body.appendChild(overlay);
      }
      toggle.addEventListener("click", () => {
        sidebar.classList.toggle("sidebar-open");
      });
      overlay.addEventListener("click", () => {
        sidebar.classList.remove("sidebar-open");
      });
    }
  }

  /* ── Session Management ─────────────────────────────────────────────── */
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

  /* ── Button Loading Helper ──────────────────────────────────────────── */
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

  /* ── Password Toggle ────────────────────────────────────────────────── */
  function togglePassword(button) {
    const input = document.getElementById(button.dataset.togglePassword);
    if (!input) return;
    const reveal = input.type === "password";
    input.type = reveal ? "text" : "password";
    button.querySelector(".eye-icon")?.classList.toggle("hidden", reveal);
    button.querySelector(".eye-off-icon")?.classList.toggle("hidden", !reveal);
    button.title = reveal ? "Sembunyikan password" : "Lihat password";
  }

  /* ── Toast Notification ─────────────────────────────────────────────── */
  function notify(message, isError = false) {
    const toastNode = document.createElement("div");
    toastNode.className = "admin-toast-card";
    toastNode.dataset.tone = isError ? "error" : "success";
    toastNode.innerHTML = `
      <span class="admin-toast-icon">
        <i data-lucide="${isError ? "alert-circle" : "check-circle-2"}"></i>
      </span>
      <span style="min-width:0">
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

  /* ── Public API ─────────────────────────────────────────────────────── */
  window.TonztoonAdmin = {
    animateCounter,
    blankPanel,
    createFeatureSession,
    createSession,
    detailRow,
    escapeHtml,
    formatDate,
    mountShell,
    normalize,
    notify,
    setButtonLoading,
    togglePassword,
    trimSlash,
    userIdFromToken,
  };
})();
