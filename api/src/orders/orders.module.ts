import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { OrderFeed } from './order-feed';
import { OrdersController } from './orders.controller';
import { OrdersService } from './orders.service';

@Module({
  imports: [AuthModule],
  controllers: [OrdersController],
  providers: [OrdersService, OrderFeed],
  exports: [OrdersService, OrderFeed],
})
export class OrdersModule {}
