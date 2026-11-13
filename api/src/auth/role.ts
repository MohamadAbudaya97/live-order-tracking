export const ROLES = ['customer', 'store', 'courier'] as const;

export type Role = (typeof ROLES)[number];

export interface AuthUser {
  id: string;
  role: Role;
  name: string;
}
