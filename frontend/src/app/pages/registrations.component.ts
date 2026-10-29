import { NgTemplateOutlet } from '@angular/common';
import { Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ForumApi } from '../core/forum-api';
import { Registration } from '../core/models';

@Component({
  selector: 'app-registrations',
  imports: [RouterLink, NgTemplateOutlet],
  templateUrl: './registrations.component.html',
})
export class RegistrationsComponent {
  private readonly api = inject(ForumApi);
  readonly upcoming = signal<Registration[]>([]);
  readonly past = signal<Registration[]>([]);
  readonly error = signal<string | null>(null);
  readonly notice = signal<string | null>(null);
  readonly confirmingId = signal<number | null>(null);
  readonly cancellingId = signal<number | null>(null);

  constructor() {
    this.load();
  }

  askCancel(registration: Registration): void {
    if (this.cancellingId() !== null) return;
    this.notice.set(null);
    this.error.set(null);
    this.confirmingId.set(registration.id);
  }

  dismissConfirm(): void {
    if (this.cancellingId() !== null) return;
    this.confirmingId.set(null);
  }

  confirmCancel(registration: Registration): void {
    if (this.cancellingId() !== null) return;
    this.cancellingId.set(registration.id);
    this.error.set(null);
    this.notice.set(null);
    this.api.cancelRegistration(registration.event_id).subscribe({
      next: () => {
        // Reload rather than patch: the server decides which section the row now belongs to, and its order.
        this.load();
        this.notice.set('Registration cancelled.');
        this.confirmingId.set(null);
        this.cancellingId.set(null);
      },
      error: (error) => {
        this.error.set(error?.error?.error?.message ?? 'Could not cancel that registration');
        this.cancellingId.set(null);
      },
    });
  }

  // In progress by the viewer's clock; the server already keeps it in Upcoming until it ends.
  happeningNow(registration: Registration): boolean {
    const event = registration.event;
    if (!event?.ends_at) return false;
    const now = Date.now();
    return new Date(event.starts_at).getTime() <= now && now < new Date(event.ends_at).getTime();
  }

  pastLabel(registration: Registration): string | null {
    if (registration.event?.status === 'cancelled' || registration.cancelled_by === 'organizer') return 'Event cancelled';
    if (registration.status === 'cancelled') return 'Cancelled';
    if (registration.status === 'failed') return 'Registration failed';
    return null;
  }

  private load(): void {
    this.api.registrations().subscribe({
      next: (response) => {
        this.upcoming.set(response.upcoming);
        this.past.set(response.past);
      },
      error: () => this.error.set('Could not load registrations'),
    });
  }
}
