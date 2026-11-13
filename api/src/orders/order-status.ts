export const ORDER_STATUSES = [
  'placed',
  'accepted',
  'preparing',
  'ready',
  'picked_up',
  'delivered',
  'cancelled',
] as const;

export type OrderStatus = (typeof ORDER_STATUSES)[number];

/**
 * Who may make a move. `owner` is the customer who placed the order, `courier` is any
 * courier, `carrier` is the one the order is assigned to.
 */
type Party = 'store' | 'owner' | 'courier' | 'carrier';

export interface Transition {
  from: OrderStatus;
  to: OrderStatus;
  by: readonly Party[];
  /** The actor becomes the order's courier. */
  assignsCourier?: true;
}

const TRANSITIONS: readonly Transition[] = [
  { from: 'placed', to: 'accepted', by: ['store'] },
  { from: 'placed', to: 'cancelled', by: ['owner', 'store'] },
  { from: 'accepted', to: 'preparing', by: ['store'] },
  { from: 'accepted', to: 'cancelled', by: ['owner', 'store'] },
  { from: 'preparing', to: 'ready', by: ['store'] },
  { from: 'preparing', to: 'cancelled', by: ['store'] },
  { from: 'ready', to: 'picked_up', by: ['courier'], assignsCourier: true },
  { from: 'picked_up', to: 'delivered', by: ['carrier'] },
];

export interface Actor {
  id: string;
  role: 'customer' | 'store' | 'courier';
}

export interface OrderParties {
  customerId: string;
  courierId: string | null;
}

export function findTransition(from: OrderStatus, to: OrderStatus): Transition | undefined {
  return TRANSITIONS.find((transition) => transition.from === from && transition.to === to);
}

export function mayPerform(transition: Transition, order: OrderParties, actor: Actor): boolean {
  return transition.by.some((party) => isParty(party, order, actor));
}

function isParty(party: Party, order: OrderParties, actor: Actor): boolean {
  switch (party) {
    case 'store':
      return actor.role === 'store';
    case 'owner':
      return actor.role === 'customer' && actor.id === order.customerId;
    case 'courier':
      return actor.role === 'courier';
    case 'carrier':
      return actor.role === 'courier' && actor.id === order.courierId;
  }
}
