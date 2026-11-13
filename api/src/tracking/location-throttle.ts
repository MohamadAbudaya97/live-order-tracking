interface Window<T> {
  timer: NodeJS.Timeout;
  latest?: T;
}

/**
 * Lets one value per key through per interval. The first value of a quiet key goes out at
 * once; values that arrive while the window is open replace each other, and the last one
 * goes out when the window closes. So a burst costs two emissions and the newest position
 * is never dropped.
 */
export class LocationThrottle<T extends object> {
  private readonly windows = new Map<string, Window<T>>();

  constructor(
    private readonly intervalMs: number,
    private readonly emit: (key: string, value: T) => void,
  ) {}

  push(key: string, value: T): void {
    const open = this.windows.get(key);
    if (open) {
      open.latest = value;
      return;
    }
    this.emit(key, value);
    this.open(key);
  }

  /** Drops whatever is waiting and cancels the timers. */
  clear(): void {
    for (const { timer } of this.windows.values()) {
      clearTimeout(timer);
    }
    this.windows.clear();
  }

  private open(key: string): void {
    this.windows.set(key, { timer: setTimeout(() => this.close(key), this.intervalMs) });
  }

  private close(key: string): void {
    const latest = this.windows.get(key)?.latest;
    this.windows.delete(key);
    if (latest) {
      // The trailing value counts against the next interval too, or a steady stream
      // would go out twice per interval.
      this.emit(key, latest);
      this.open(key);
    }
  }
}
