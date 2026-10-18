import { Component, inject, signal } from '@angular/core';
import { ForumApi } from '../core/forum-api';
import { NotificationItem } from '../core/models';

@Component({
  selector: 'app-notifications',
  templateUrl: './notifications.component.html',
})
export class NotificationsComponent {
  private readonly api = inject(ForumApi);
  readonly notifications = signal<NotificationItem[]>([]);
  readonly error = signal<string | null>(null);

  constructor() {
    this.api.notifications().subscribe({
      next: (response) => this.notifications.set(response.data),
      error: () => this.error.set('Could not load notifications'),
    });
  }
}
