import { ORDER_STATUSES, findTransition, mayPerform } from './order-status';
import type { Actor, OrderParties, OrderStatus } from './order-status';

const owner: Actor = { id: 'customer-1', role: 'customer' };
const stranger: Actor = { id: 'customer-2', role: 'customer' };
const store: Actor = { id: 'store-1', role: 'store' };
const courier: Actor = { id: 'courier-1', role: 'courier' };
const otherCourier: Actor = { id: 'courier-2', role: 'courier' };

const unassigned: OrderParties = { customerId: owner.id, courierId: null };
const carried: OrderParties = { customerId: owner.id, courierId: courier.id };

function allowed(from: OrderStatus, to: OrderStatus, actor: Actor, order = unassigned): boolean {
  const transition = findTransition(from, to);
  if (!transition) {
    throw new Error(`${from} → ${to} is not a transition`);
  }
  return mayPerform(transition, order, actor);
}

describe('order status machine', () => {
  it('has exactly the transitions of the contract', () => {
    const known = ORDER_STATUSES.flatMap((from) =>
      ORDER_STATUSES.filter((to) => findTransition(from, to)).map((to) => `${from} → ${to}`),
    );

    expect(known).toEqual([
      'placed → accepted',
      'placed → cancelled',
      'accepted → preparing',
      'accepted → cancelled',
      'preparing → ready',
      'preparing → cancelled',
      'ready → picked_up',
      'picked_up → delivered',
    ]);
  });

  it.each<OrderStatus>(['delivered', 'cancelled'])('treats %s as final', (status) => {
    for (const to of ORDER_STATUSES) {
      expect(findTransition(status, to)).toBeUndefined();
    }
  });

  it.each<[OrderStatus, OrderStatus, string, Actor, OrderParties]>([
    ['placed', 'accepted', 'the store', store, unassigned],
    ['placed', 'cancelled', 'the customer who placed it', owner, unassigned],
    ['placed', 'cancelled', 'the store', store, unassigned],
    ['accepted', 'preparing', 'the store', store, unassigned],
    ['accepted', 'cancelled', 'the customer who placed it', owner, unassigned],
    ['accepted', 'cancelled', 'the store', store, unassigned],
    ['preparing', 'ready', 'the store', store, unassigned],
    ['preparing', 'cancelled', 'the store', store, unassigned],
    ['ready', 'picked_up', 'any courier', courier, unassigned],
    ['picked_up', 'delivered', 'the courier carrying it', courier, carried],
  ])('allows %s → %s by %s', (from, to, _who, actor, order) => {
    expect(allowed(from, to, actor, order)).toBe(true);
  });

  it.each<[OrderStatus, OrderStatus, string, Actor, OrderParties]>([
    ['placed', 'accepted', 'the customer', owner, unassigned],
    ['placed', 'accepted', 'a courier', courier, unassigned],
    ['placed', 'cancelled', 'another customer', stranger, unassigned],
    ['placed', 'cancelled', 'a courier', courier, unassigned],
    ['accepted', 'cancelled', 'another customer', stranger, unassigned],
    ['preparing', 'ready', 'the customer', owner, unassigned],
    ['preparing', 'cancelled', 'the customer, once the kitchen has started', owner, unassigned],
    ['ready', 'picked_up', 'the store', store, unassigned],
    ['ready', 'picked_up', 'the customer', owner, unassigned],
    ['picked_up', 'delivered', 'the store', store, carried],
    ['picked_up', 'delivered', 'the customer', owner, carried],
    ['picked_up', 'delivered', 'a courier who is not carrying it', otherCourier, carried],
  ])('forbids %s → %s by %s', (from, to, _who, actor, order) => {
    expect(allowed(from, to, actor, order)).toBe(false);
  });

  it('assigns a courier on pick-up and nowhere else', () => {
    const assigning = ORDER_STATUSES.flatMap((from) =>
      ORDER_STATUSES.map((to) => findTransition(from, to)).filter((t) => t?.assignsCourier),
    );

    expect(assigning).toEqual([expect.objectContaining({ from: 'ready', to: 'picked_up' })]);
  });
});
