import { Injectable } from '@nestjs/common';
import { Subject } from 'rxjs';
import type { CourierLocationUpdate, OrderEvent } from './order.types';

/**
 * What happened to orders, for whoever wants to push it to clients. The orders module
 * publishes here only after the transaction has committed and does not know who listens.
 */
@Injectable()
export class OrderFeed {
  readonly events = new Subject<OrderEvent>();
  readonly locations = new Subject<CourierLocationUpdate>();
}
