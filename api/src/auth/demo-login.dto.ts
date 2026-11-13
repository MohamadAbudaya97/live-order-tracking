import { Transform } from 'class-transformer';
import { IsIn, IsString, Length } from 'class-validator';
import { ROLES } from './role';
import type { Role } from './role';

export class DemoLoginDto {
  @IsIn(ROLES)
  role!: Role;

  @Transform(({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(1, 40)
  name!: string;
}
