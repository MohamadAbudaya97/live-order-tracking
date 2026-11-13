import { OnModuleDestroy } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
} from '@nestjs/websockets';
import { Subscription } from 'rxjs';
import type { DefaultEventsMap, Namespace, Socket } from 'socket.io';
import { AuthService } from '../auth/auth.service';
import type { AuthUser } from '../auth/role';
import { ApiError } from '../common/api-error';
import type { ErrorCode } from '../common/api-error';
import { OrderFeed } from '../orders/order-feed';
import type { CourierLocationUpdate, Order, OrderEvent } from '../orders/order.types';
import { OrdersService } from '../orders/orders.service';
import { LocationThrottle } from './location-throttle';
import { SubscribeDto, UnsubscribeDto, parsePayload } from './tracking.dto';

const LOCATION_INTERVAL_MS = 1000;

interface ServerEvents {
  'order.event': (event: OrderEvent) => void;
  'courier.location': (location: CourierLocationUpdate) => void;
}

interface SocketData {
  user: AuthUser;
}

type TrackingNamespace = Namespace<DefaultEventsMap, ServerEvents, DefaultEventsMap, SocketData>;
type TrackingSocket = Socket<DefaultEventsMap, ServerEvents, DefaultEventsMap, SocketData>;

type Failure = { ok: false; code: ErrorCode };
type SubscribeAck = { ok: true; snapshot: Order; missed: OrderEvent[] } | Failure;
type UnsubscribeAck = { ok: true } | Failure;

const roomOf = (orderId: string) => `order:${orderId}`;

@WebSocketGateway({ namespace: 'tracking' })
export class TrackingGateway implements OnGatewayInit<TrackingNamespace>, OnModuleDestroy {
  private namespace!: TrackingNamespace;
  private readonly feedSubscription = new Subscription();
  private readonly throttle = new LocationThrottle<CourierLocationUpdate>(
    LOCATION_INTERVAL_MS,
    (orderId, location) => this.namespace.to(roomOf(orderId)).emit('courier.location', location),
  );

  constructor(
    private readonly auth: AuthService,
    private readonly orders: OrdersService,
    private readonly feed: OrderFeed,
  ) {}

  afterInit(namespace: TrackingNamespace): void {
    this.namespace = namespace;

    // Rejecting in a namespace middleware is what gives the client a `connect_error`
    // with our message; disconnecting after the connection would not.
    namespace.use((socket, next) => {
      try {
        socket.data.user = this.auth.verify(socket.handshake.auth.token);
        next();
      } catch {
        next(new Error('UNAUTHENTICATED'));
      }
    });

    this.feedSubscription.add(this.feed.events.subscribe((event) => void this.broadcast(event)));
    this.feedSubscription.add(
      this.feed.locations.subscribe((location) => this.throttle.push(location.orderId, location)),
    );
  }

  onModuleDestroy(): void {
    this.feedSubscription.unsubscribe();
    this.throttle.clear();
  }

  @SubscribeMessage('subscribe')
  async subscribe(
    @ConnectedSocket() socket: TrackingSocket,
    @MessageBody() payload: unknown,
  ): Promise<SubscribeAck> {
    const dto = parsePayload(SubscribeDto, payload);
    if (!dto) {
      return { ok: false, code: 'VALIDATION_FAILED' };
    }
    const { orderId, afterSeq } = dto;
    const { user } = socket.data;
    const room = roomOf(orderId);

    try {
      // Checked before joining, so a socket is never in a room it may not listen to.
      await this.orders.get(orderId, user);
      await socket.join(room);
      // Read after joining: a change committed from here on also arrives live, and the
      // client drops the duplicate by seq. Read before, it could be in neither.
      const snapshot = await this.orders.get(orderId, user);
      const missed =
        typeof afterSeq === 'number' ? await this.orders.events(orderId, user, afterSeq) : [];
      return { ok: true, snapshot, missed };
    } catch (error) {
      if (error instanceof ApiError) {
        // The order can stop being visible between the check and the read.
        await socket.leave(room);
        return { ok: false, code: error.code };
      }
      throw error;
    }
  }

  @SubscribeMessage('unsubscribe')
  async unsubscribe(
    @ConnectedSocket() socket: TrackingSocket,
    @MessageBody() payload: unknown,
  ): Promise<UnsubscribeAck> {
    const dto = parsePayload(UnsubscribeDto, payload);
    if (!dto) {
      return { ok: false, code: 'VALIDATION_FAILED' };
    }
    await socket.leave(roomOf(dto.orderId));
    return { ok: true };
  }

  private async broadcast(event: OrderEvent): Promise<void> {
    const room = roomOf(event.orderId);
    this.namespace.to(room).emit('order.event', event);

    // Every courier may watch a ready order, but only the one who picks it up may keep
    // watching. The others still receive the pick-up above, which is how they learn to
    // drop it; after that they are out of the room.
    if (event.type === 'order.status_changed' && event.data.to === 'picked_up') {
      const sockets = await this.namespace.in(room).fetchSockets();
      for (const socket of sockets) {
        const { user } = socket.data;
        if (user.role === 'courier' && user.id !== event.data.courierId) {
          socket.leave(room);
        }
      }
    }
  }
}
