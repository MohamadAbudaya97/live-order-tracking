import { Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { unauthenticated } from '../common/api-error';
import { PrismaService } from '../prisma/prisma.service';
import { DemoLoginDto } from './demo-login.dto';
import type { AuthUser, Role } from './role';

interface TokenClaims {
  sub: string;
  role: Role;
  name: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  async demoLogin({ role, name }: DemoLoginDto): Promise<{ token: string; user: AuthUser }> {
    const user = await this.prisma.user.upsert({
      where: { role_name: { role, name } },
      create: { role, name },
      update: {},
      select: { id: true, role: true, name: true },
    });
    const claims: TokenClaims = { sub: user.id, role: user.role, name: user.name };
    return { token: await this.jwt.signAsync(claims), user };
  }

  /**
   * The token carries the role and the name, so a request is authenticated without a query.
   * That is safe here because a demo user never changes after it is created.
   */
  verify(token: unknown): AuthUser {
    if (typeof token !== 'string') {
      throw unauthenticated();
    }
    try {
      const { sub, role, name } = this.jwt.verify<TokenClaims>(token);
      return { id: sub, role, name };
    } catch {
      throw unauthenticated();
    }
  }
}
