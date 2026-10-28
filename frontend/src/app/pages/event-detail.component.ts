import { DatePipe } from '@angular/common';
import { Component, DestroyRef, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { catchError, of, switchMap } from 'rxjs';
import { AdminOrganizationsService } from '../core/admin-organizations.service';
import { ForumApi } from '../core/forum-api';
import { EventSummary } from '../core/models';

@Component({
  selector: 'app-event-detail',
  imports: [RouterLink, DatePipe],
  templateUrl: './event-detail.component.html',
})
export class EventDetailComponent {
  private readonly api = inject(ForumApi);
  private readonly route = inject(ActivatedRoute);
  private readonly adminOrganizations = inject(AdminOrganizationsService);

  readonly event = signal<EventSummary | null>(null);
  readonly error = signal<string | null>(null);
  readonly message = signal<string | null>(null);
  readonly confirmingCancel = signal(false);
  readonly cancelling = signal(false);

  readonly cancelled = computed(() => this.event()?.status === 'cancelled');
  // Only the organizer's admins may cancel, and only a published event that has not started.
  readonly canCancel = computed(() => {
    const event = this.event();
    if (!event || event.status !== 'published' || new Date(event.starts_at) <= new Date()) return false;
    return this.adminOrganizations.organizations().some((organization) => organization.id === event.organization.id);
  });

  constructor() {
    this.adminOrganizations.ensureLoaded();

    this.route.paramMap
      .pipe(
        switchMap((params) => this.api.event(Number(params.get('id')))),
        catchError(() => {
          this.error.set('Event not found');
          return of(null);
        }),
        takeUntilDestroyed(inject(DestroyRef)),
      )
      .subscribe((event) => this.event.set(event));
  }

  register(): void {
    const event = this.event();
    if (!event) return;
    this.api.register(event.id).subscribe({
      next: () => this.message.set('You are registered.'),
      error: (error) => this.message.set(error?.error?.error?.message ?? 'Registration failed'),
    });
  }

  askCancel(): void {
    if (this.cancelling()) return;
    this.message.set(null);
    this.confirmingCancel.set(true);
  }

  keepEvent(): void {
    if (this.cancelling()) return;
    this.confirmingCancel.set(false);
  }

  confirmCancel(): void {
    const event = this.event();
    if (!event || this.cancelling()) return;
    this.cancelling.set(true);
    this.api.cancelEvent(event.id).subscribe({
      next: (updated) => {
        this.event.set(updated);
        this.message.set('Event cancelled. Registrants are being notified.');
        this.confirmingCancel.set(false);
        this.cancelling.set(false);
      },
      error: (error) => {
        this.message.set(error?.error?.error?.message ?? 'Could not cancel the event');
        this.cancelling.set(false);
      },
    });
  }
}
