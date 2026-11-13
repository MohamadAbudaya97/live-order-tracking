import { Body, Controller, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { DemoLoginDto } from './demo-login.dto';
import type { AuthUser } from './role';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('demo-login')
  demoLogin(@Body() dto: DemoLoginDto): Promise<{ token: string; user: AuthUser }> {
    return this.auth.demoLogin(dto);
  }
}
