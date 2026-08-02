type ReportFn = (seconds: number) => Promise<void>;

/** 浏览器端有效学习时长：前台可见且未空闲时累计，定期上报。 */
export class StudyDurationTracker {
  private accumulated = 0;
  private segmentStartedAt: number | null = null;
  private lastInteractionAt = Date.now();
  private tracking = false;
  private visible = typeof document === "undefined" ? true : !document.hidden;
  private timer: number | null = null;
  private readonly idleTimeoutMs: number;
  private readonly flushIntervalMs: number;
  private readonly report: ReportFn;

  constructor(
    report: ReportFn,
    options?: { idleTimeoutMs?: number; flushIntervalMs?: number },
  ) {
    this.report = report;
    this.idleTimeoutMs = options?.idleTimeoutMs ?? 60_000;
    this.flushIntervalMs = options?.flushIntervalMs ?? 15_000;
  }

  start() {
    if (this.tracking) return;
    this.tracking = true;
    this.lastInteractionAt = Date.now();
    this.visible = !document.hidden;
    if (this.visible) this.beginSegment();
    this.timer = window.setInterval(() => {
      void this.tickAndFlush();
    }, this.flushIntervalMs);
    document.addEventListener("visibilitychange", this.onVisibility);
    window.addEventListener("pointerdown", this.onInteraction);
    window.addEventListener("keydown", this.onInteraction);
  }

  stop() {
    if (!this.tracking) return;
    this.tracking = false;
    if (this.timer != null) {
      window.clearInterval(this.timer);
      this.timer = null;
    }
    document.removeEventListener("visibilitychange", this.onVisibility);
    window.removeEventListener("pointerdown", this.onInteraction);
    window.removeEventListener("keydown", this.onInteraction);
    this.endSegment();
    void this.flushNow();
  }

  noteInteraction() {
    this.lastInteractionAt = Date.now();
    if (this.tracking && this.visible && this.segmentStartedAt == null) {
      this.beginSegment();
    }
  }

  private onVisibility = () => {
    this.visible = !document.hidden;
    if (!this.tracking) return;
    if (this.visible) {
      this.lastInteractionAt = Date.now();
      this.beginSegment();
    } else {
      this.endSegment();
      void this.flushNow();
    }
  };

  private onInteraction = () => {
    this.noteInteraction();
  };

  private beginSegment() {
    if (this.segmentStartedAt == null) {
      this.segmentStartedAt = Date.now();
    }
  }

  private endSegment() {
    if (this.segmentStartedAt == null) return;
    const now = Date.now();
    const idleCut = this.lastInteractionAt + this.idleTimeoutMs;
    const effectiveEnd = Math.min(now, idleCut);
    const seconds = Math.max(
      0,
      Math.floor((effectiveEnd - this.segmentStartedAt) / 1000),
    );
    if (seconds > 0) this.accumulated += seconds;
    this.segmentStartedAt = null;
  }

  private async tickAndFlush() {
    if (!this.tracking) return;
    if (this.visible) {
      if (Date.now() > this.lastInteractionAt + this.idleTimeoutMs) {
        this.endSegment();
      } else if (this.segmentStartedAt == null) {
        this.beginSegment();
      } else {
        this.endSegment();
        this.beginSegment();
      }
    }
    await this.flushNow();
  }

  private async flushNow() {
    const seconds = this.accumulated;
    if (seconds <= 0) return;
    this.accumulated = 0;
    try {
      await this.report(seconds);
    } catch {
      this.accumulated += seconds;
    }
  }
}
