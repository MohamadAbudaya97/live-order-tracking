import { randomInt } from 'node:crypto';

// No 0/O, 1/I/L or other pairs that sound or look alike when a code is read out over a counter.
const ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const LENGTH = 4;

/**
 * A short label for people, not an identifier: two orders may share a code, and nothing
 * looks an order up by it.
 */
export function newOrderCode(): string {
  return Array.from({ length: LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');
}
