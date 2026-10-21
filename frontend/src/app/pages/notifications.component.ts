import { DatePipe } from '@angular/common';
import { Component, DestroyRef, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ForumApi } from '../core/forum-api';
import { NotificationItem, NotificationPreferences } from '../core/models';

@Component({
  selector: 'app-notifications',
  imports: [DatePipe],
  templateUrl: './notifications.component.html',
})
export class NotificationsComponent {
  private readonly api = inject(ForumApi);
  private readonly destroyRef = inject(DestroyRef);

  readonly notifications = signal<NotificationItem[]>([]);
  readonly preferences = signal<NotificationPreferences | null>(null);
  readonly unreadCount = signal(0);
  readonly nextCursor = signal<string | null>(null);
  readonly loading = signal(true);
  readonly loadingMore = signal(false);
  readonly markingAll = signal(false);
  readonly markingId = signal<number | null>(null);
  readonly savingPreference = signal(false);
  readonly error = signal<string | null>(null);

  constructor() {
    this.loadPage(null, false);
    this.api.notificationPreferences().pipe(takeUntilDestroyed()).subscribe({
      next: (preferences) => this.preferences.set(preferences),
      error: () => this.error.set('Could not load notification preferences'),
    });
  }

  loadOlder(): void {
    const cursor = this.nextCursor();
    if (!cursor || this.loadingMore()) return;
    this.loadPage(cursor, true);
  }

  markRead(notification: NotificationItem): void {
    if (notification.read_at || this.markingId() === notification.id) return;

    this.markingId.set(notification.id);
    this.error.set(null);
    this.api.markNotificationRead(notification.id).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (updated) => {
        this.notifications.update((rows) => rows.map((row) => (row.id === updated.id ? { ...row, read_at: updated.read_at } : row)));
        this.unreadCount.set(updated.unread_count);
        this.markingId.set(null);
      },
      error: () => {
        this.error.set('Could not mark notification as read');
        this.markingId.set(null);
      },
    });
  }

  markAll(): void {
    if (this.markingAll() || this.unreadCount() === 0) return;

    this.markingAll.set(true);
    this.error.set(null);
    this.api.markAllNotificationsRead().pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (response) => {
        this.notifications.update((rows) => rows.map((row) => ({ ...row, read_at: row.read_at ?? new Date().toISOString() })));
        this.unreadCount.set(response.unread_count);
        this.markingAll.set(false);
      },
      error: () => {
        this.error.set('Could not mark notifications as read');
        this.markingAll.set(false);
      },
    });
  }

  setPreference(field: keyof NotificationPreferences, enabled: boolean): void {
    const current = this.preferences();
    if (!current || this.savingPreference()) return;

    const next = { ...current, [field]: enabled };
    this.preferences.set(next);
    this.savingPreference.set(true);
    this.error.set(null);
    this.api.updateNotificationPreferences(next).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (preferences) => {
        this.preferences.set(preferences);
        this.savingPreference.set(false);
      },
      error: () => {
        this.preferences.set(current);
        this.error.set('Could not save notification preferences');
        this.savingPreference.set(false);
      },
    });
  }

  private loadPage(cursor: string | null, append: boolean): void {
    if (append) this.loadingMore.set(true);
    else this.loading.set(true);

    this.api.notifications(cursor).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (response) => {
        this.notifications.update((rows) => (append ? [...rows, ...response.data] : response.data));
        this.unreadCount.set(response.unread_count);
        this.nextCursor.set(response.next_cursor);
        this.loading.set(false);
        this.loadingMore.set(false);
      },
      error: () => {
        this.error.set('Could not load notifications');
        this.loading.set(false);
        this.loadingMore.set(false);
      },
    });
  }
}
