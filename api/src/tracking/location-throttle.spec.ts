import { LocationThrottle } from './location-throttle';

interface Position {
  lat: number;
}

const INTERVAL = 1000;

describe('LocationThrottle', () => {
  let sent: [string, Position][];
  let throttle: LocationThrottle<Position>;

  beforeEach(() => {
    jest.useFakeTimers();
    sent = [];
    throttle = new LocationThrottle<Position>(INTERVAL, (key, value) => sent.push([key, value]));
  });

  afterEach(() => {
    throttle.clear();
    jest.useRealTimers();
  });

  it('sends the first position at once', () => {
    throttle.push('order-a', { lat: 1 });

    expect(sent).toEqual([['order-a', { lat: 1 }]]);
  });

  it('turns a burst into the first position now and the latest when the interval ends', () => {
    for (const lat of [1, 2, 3, 4]) {
      throttle.push('order-a', { lat });
    }
    expect(sent).toEqual([['order-a', { lat: 1 }]]);

    jest.advanceTimersByTime(INTERVAL - 1);
    expect(sent).toHaveLength(1);

    jest.advanceTimersByTime(1);
    expect(sent).toEqual([
      ['order-a', { lat: 1 }],
      ['order-a', { lat: 4 }],
    ]);
  });

  it('sends nothing when the interval ends with nothing waiting', () => {
    throttle.push('order-a', { lat: 1 });

    jest.advanceTimersByTime(INTERVAL * 5);

    expect(sent).toHaveLength(1);
  });

  it('sends at once again after a quiet interval', () => {
    throttle.push('order-a', { lat: 1 });
    jest.advanceTimersByTime(INTERVAL);

    throttle.push('order-a', { lat: 2 });

    expect(sent).toEqual([
      ['order-a', { lat: 1 }],
      ['order-a', { lat: 2 }],
    ]);
  });

  it('holds a steady stream to one position per interval', () => {
    for (let lat = 0; lat < 30; lat++) {
      throttle.push('order-a', { lat });
      jest.advanceTimersByTime(INTERVAL / 10);
    }

    expect(sent.map(([, position]) => position.lat)).toEqual([0, 9, 19, 29]);
  });

  it('gives every order its own interval', () => {
    throttle.push('order-a', { lat: 1 });
    throttle.push('order-b', { lat: 10 });
    throttle.push('order-a', { lat: 2 });

    expect(sent).toEqual([
      ['order-a', { lat: 1 }],
      ['order-b', { lat: 10 }],
    ]);

    jest.advanceTimersByTime(INTERVAL);
    expect(sent).toEqual([
      ['order-a', { lat: 1 }],
      ['order-b', { lat: 10 }],
      ['order-a', { lat: 2 }],
    ]);
  });

  it('forgets what is waiting when cleared', () => {
    throttle.push('order-a', { lat: 1 });
    throttle.push('order-a', { lat: 2 });

    throttle.clear();
    jest.advanceTimersByTime(INTERVAL * 5);

    expect(sent).toEqual([['order-a', { lat: 1 }]]);
  });
});
