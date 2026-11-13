import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { OrdersModule } from '../orders/orders.module';
import { TrackingGateway } from './tracking.gateway';

@Module({
  imports: [AuthModule, OrdersModule],
  providers: [TrackingGateway],
})
export class TrackingModule {}
