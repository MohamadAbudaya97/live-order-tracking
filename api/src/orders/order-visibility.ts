import type { AuthUser } from '../auth/role';
import type { Prisma } from '../prisma-client/client';

/**
 * The orders a user may see, as a query filter. Lists and single reads both go through
 * it, so the rule is written once.
 */
export function visibleTo(user: AuthUser): Prisma.OrderWhereInput {
  switch (user.role) {
    case 'customer':
      return { customerId: user.id };
    case 'store':
      return {};
    case 'courier':
      return { OR: [{ status: 'ready', courierId: null }, { courierId: user.id }] };
  }
}
