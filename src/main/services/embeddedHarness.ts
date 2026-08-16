import { shell, WebContentsView, type BrowserWindow } from 'electron'
import type { WebBounds, WebNavigationState } from '@shared/types'

/** 在应用窗口内嵌官方 dsh Web UI（独立 WebContents，可注入会话恢复脚本）。 */
export class EmbeddedHarness {
  private view: WebContentsView | null = null
  private window: BrowserWindow | null = null
  private loaded = false
  private pendingSession: { id: string; title: string } | null = null
  private bounds: WebBounds = { x: 0, y: 0, width: 0, height: 0 }

  constructor(
    private onNavigation: (state: WebNavigationState) => void,
    private onSessionOpenResult: (sessionId: string, opened: boolean) => void
  ) {}

  get isAttached(): boolean {
    return this.view !== null
  }

  attach(window: BrowserWindow, initialBounds: WebBounds): void {
    if (this.view) return
    this.window = window
    this.bounds = initialBounds

    const view = new WebContentsView({
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
        javascript: true
      }
    })
    this.view = view
    window.contentView.addChildView(view)
    this.applyBounds()

    const contents = view.webContents
    contents.on('did-start-loading', () => this.emitNavigation())
    contents.on('did-stop-loading', () => this.emitNavigation())
    contents.on('did-finish-load', () => {
      this.loaded = true
      this.emitNavigation()
      if (this.pendingSession) {
        const pending = this.pendingSession
        this.pendingSession = null
        void this.attemptOpenSession(pending.id, pending.title)
      }
    })
    contents.on('did-navigate', () => this.emitNavigation())
    contents.on('did-navigate-in-page', () => this.emitNavigation())
    contents.setWindowOpenHandler(({ url }) => {
      void shell.openExternal(url)
      return { action: 'deny' }
    })
    contents.on('will-navigate', (event, url) => {
      const allowed = /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\])(:\d+)?\//.test(url)
      if (!allowed) {
        event.preventDefault()
        void shell.openExternal(url)
      }
    })
  }

  setBounds(bounds: WebBounds): void {
    this.bounds = bounds
    this.applyBounds()
  }

  async load(url: string): Promise<void> {
    if (!this.view) return
    this.loaded = false
    await this.view.webContents.loadURL(url).catch(() => undefined)
  }

  openSession(id: string, title: string): void {
    if (!this.loaded) {
      this.pendingSession = { id, title }
      return
    }
    void this.attemptOpenSession(id, title)
  }

  async reload(): Promise<void> {
    this.view?.webContents.reload()
  }

  goBack(): void {
    if (this.view?.webContents.canGoBack()) this.view.webContents.goBack()
  }

  goForward(): void {
    if (this.view?.webContents.canGoForward()) this.view.webContents.goForward()
  }

  zoomIn(): void {
    if (!this.view) return
    const current = this.view.webContents.getZoomFactor()
    this.view.webContents.setZoomFactor(Math.min(current + 0.1, 2.0))
    this.emitNavigation()
  }

  zoomOut(): void {
    if (!this.view) return
    const current = this.view.webContents.getZoomFactor()
    this.view.webContents.setZoomFactor(Math.max(current - 0.1, 0.5))
    this.emitNavigation()
  }

  zoomReset(): void {
    this.view?.webContents.setZoomFactor(1)
    this.emitNavigation()
  }

  destroy(): void {
    this.loaded = false
    this.pendingSession = null
    if (this.view && this.window && !this.window.isDestroyed()) {
      this.window.contentView.removeChildView(this.view)
    }
    this.view?.webContents.close()
    this.view = null
    this.window = null
  }

  // MARK: - 内部

  private applyBounds(): void {
    if (!this.view || !this.window || this.window.isDestroyed()) return
    const { x, y, width, height } = this.bounds
    const clampedWidth = Math.max(1, Math.round(width))
    const clampedHeight = Math.max(1, Math.round(height))
    this.view.setBounds({ x: Math.max(0, Math.round(x)), y: Math.max(0, Math.round(y)), width: clampedWidth, height: clampedHeight })
  }

  private emitNavigation(): void {
    if (!this.view) return
    const contents = this.view.webContents
    this.onNavigation({
      canGoBack: contents.canGoBack(),
      canGoForward: contents.canGoForward(),
      zoomFactor: contents.getZoomFactor(),
      loading: contents.isLoading(),
      title: contents.getTitle() || 'DeepSeek Harness'
    })
  }

  private async attemptOpenSession(id: string, title: string, attemptsRemaining = 24): Promise<void> {
    if (!this.view || attemptsRemaining <= 0) {
      this.onSessionOpenResult(id, false)
      return
    }
    const script = buildSessionScript(id, title)
    try {
      const result = (await this.view.webContents.executeJavaScript(script)) as string
      const object = JSON.parse(result) as { ok?: boolean }
      if (object.ok) {
        this.onSessionOpenResult(id, true)
        return
      }
    } catch {
      // 页面尚未渲染完成，继续重试。
    }
    setTimeout(() => {
      void this.attemptOpenSession(id, title, attemptsRemaining - 1)
    }, 500)
  }
}

function buildSessionScript(id: string, title: string): string {
  const idJSON = JSON.stringify(id)
  const titleJSON = JSON.stringify(title)
  return `(function () {
  function fiberOf(el) {
    var key = Object.keys(el).find(function (k) { return k.indexOf('__reactFiber') === 0; });
    return key ? el[key] : null;
  }
  function nameOf(f) {
    if (!f) return '';
    if (f.elementType && f.elementType.name) return String(f.elementType.name);
    return typeof f.type === 'string' ? f.type : '';
  }
  var target = ${idJSON};
  var title = ${titleJSON};
  var rows = Array.from(document.querySelectorAll('[role="treeitem"]'));
  for (var i = 0; i < rows.length; i++) {
    var f = fiberOf(rows[i]);
    while (f) {
      if (nameOf(f) === 'SessionNodeItem') {
        var node = f.memoizedProps && f.memoizedProps.node;
        if (node && node.id === target) {
          rows[i].click();
          return JSON.stringify({ ok: true, via: 'id' });
        }
      }
      f = f.return;
    }
  }
  if (title) {
    var norm = function (s) { return (s || '').trim().replace(/\\s+/g, ' '); };
    var prefix = norm(title).slice(0, 18);
    for (var j = 0; j < rows.length; j++) {
      var span = rows[j].querySelector('.YDXeBa_title');
      if (span && norm(span.textContent).slice(0, prefix.length) === prefix && prefix.length > 0) {
        rows[j].click();
        return JSON.stringify({ ok: true, via: 'title' });
      }
    }
  }
  return JSON.stringify({ ok: false });
})()`
}
